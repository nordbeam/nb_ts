use rustler::NifResult;
use oxc_allocator::Allocator;
use oxc_parser::Parser;
use oxc_semantic::SemanticBuilder;
use oxc_span::SourceType;

#[rustler::nif]
fn validate(typescript_code: String) -> NifResult<Result<String, String>> {
    // Create allocator for AST
    let allocator = Allocator::default();

    // Configure TypeScript source type
    // Parse as a TypeScript module (.ts) to handle imports and exports
    let source_type = SourceType::from_path("check.ts")
        .unwrap_or_else(|_| SourceType::default().with_typescript(true).with_module(true));

    // If the input doesn't look like a complete statement (no 'export', 'type', 'interface'),
    // wrap it as a type alias to validate the type expression
    let code_to_validate = if typescript_code.trim_start().starts_with("export")
        || typescript_code.trim_start().starts_with("type ")
        || typescript_code.trim_start().starts_with("interface ")
        || typescript_code.trim_start().starts_with("declare ") {
        typescript_code.clone()
    } else {
        // Wrap bare type expression in a type alias
        format!("type __ValidationType = {};", typescript_code)
    };

    // Parse the TypeScript code
    // Wrap in panic catch since oxc may panic on certain edge cases
    let parser_return = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        Parser::new(&allocator, &code_to_validate, source_type).parse()
    }));

    let parser_return = match parser_return {
        Ok(result) => result,
        Err(_) => {
            // Parser panicked - likely a bug in oxc or unsupported syntax
            // Fall back to basic validation
            return Ok(Err("TypeScript parser encountered an unrecoverable error".to_string()));
        }
    };

    // Check for parser panic (unrecoverable error)
    if parser_return.panicked {
        return Ok(Err("TypeScript parser encountered an unrecoverable error".to_string()));
    }

    // Check for parser syntax errors first
    if !parser_return.errors.is_empty() {
        let errors: Vec<String> = parser_return.errors
            .iter()
            .map(|e| format!("{}", e))
            .collect();

        return Ok(Err(format!("TypeScript syntax error: {}", errors.join("; "))));
    }

    // Run semantic analysis with strict syntax error checking enabled
    // This catches errors that the parser defers for performance
    // Note: Semantic analysis may fail on isolated type definitions with imports
    // We only use it as an additional validation step, not as a hard requirement
    //
    // Wrap in a catch to handle panics (e.g., from module resolution)
    let semantic_return = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        SemanticBuilder::new()
            .with_check_syntax_error(true)
            .build(&parser_return.program)
    }));

    // If semantic analysis panicked, just skip it and return success
    // (parser validation was already successful)
    let semantic_return = match semantic_return {
        Ok(result) => result,
        Err(_) => {
            // Semantic analysis failed (likely module resolution)
            // But parser succeeded, so the syntax is valid
            return Ok(Ok(typescript_code));
        }
    };

    // Only report semantic errors if there are actual syntax issues
    // (not just missing module resolution)
    if !semantic_return.errors.is_empty() {
        // Filter out module resolution errors since we're validating isolated files
        let syntax_errors: Vec<String> = semantic_return.errors
            .iter()
            .filter(|e| {
                let msg = format!("{}", e);
                // Keep only actual syntax errors, not module resolution issues
                !msg.contains("Cannot find") && !msg.contains("module")
            })
            .map(|e| format!("{}", e))
            .collect();

        if !syntax_errors.is_empty() {
            return Ok(Err(format!("TypeScript syntax error: {}", syntax_errors.join("; "))));
        }
    }

    // Validation successful - return original code
    Ok(Ok(typescript_code))
}

rustler::init!("Elixir.NbTs.Validator");
