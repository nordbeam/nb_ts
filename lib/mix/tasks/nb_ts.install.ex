if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.NbTs.Install do
    @moduledoc """
    Installs and configures NbTs in a Phoenix application using Igniter.

    This installer:
    1. Adds nb_ts dependency to mix.exs
    2. Creates the TypeScript output directory
    3. Creates or updates tsconfig.json
    4. Adds mix alias for type generation
    5. Optionally sets up file watcher for auto-generation
    6. Creates example file with ~TS sigil usage
    7. Runs initial type generation

    ## Usage

        $ mix nb_ts.install

    ## Options

        --output-dir   Where to generate TypeScript types (default: "assets/js/types")
        --watch-mode   Set up file watcher for automatic type generation
        --yes          Skip confirmations

    ## Examples

        # Basic installation
        mix nb_ts.install

        # Install with custom output directory
        mix nb_ts.install --output-dir assets/types

        # Install with file watcher for auto-generation
        mix nb_ts.install --watch-mode

        # Install without confirmations
        mix nb_ts.install --yes
    """

    use Igniter.Mix.Task

    def supports_umbrella?, do: true

    @impl Igniter.Mix.Task
    def info(_argv, _parent) do
      %Igniter.Mix.Task.Info{
        schema: [
          output_dir: :string,
          watch_mode: :boolean,
          yes: :boolean
        ],
        defaults: [
          output_dir: "assets/js/types"
        ],
        positional: [],
        composes: ["deps.get"]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      output_dir = igniter.args.options[:output_dir] || "assets/js/types"

      igniter
      |> add_nb_ts_dependency()
      |> create_output_directory(output_dir)
      |> create_or_update_tsconfig(output_dir)
      |> add_type_generation_alias()
      |> maybe_setup_watcher(output_dir)
      |> create_example_file()
      |> add_initial_type_generation_task()
      |> print_usage_instructions(output_dir)
    end

    defp add_nb_ts_dependency(igniter) do
      Igniter.Project.Deps.add_dep(igniter, {:nb_ts, "~> 0.1"})
    end

    defp create_output_directory(igniter, output_dir) do
      # Create a .gitkeep file to ensure the directory exists
      gitkeep_path = Path.join(output_dir, ".gitkeep")

      igniter
      |> Igniter.create_new_file(gitkeep_path, "", on_exists: :skip)
      |> Igniter.add_notice("""
      Created TypeScript output directory at #{output_dir}

      Generated TypeScript types will be placed here.
      """)
    end

    defp create_or_update_tsconfig(igniter, output_dir) do
      tsconfig_path = Path.join(Path.dirname(output_dir), "tsconfig.json")

      # Calculate the relative path from tsconfig location to types directory
      types_dir = Path.basename(output_dir)

      tsconfig_content = """
      {
        "compilerOptions": {
          "baseUrl": ".",
          "paths": {
            "@/*": ["./js/*"]
          },
          "target": "ES2020",
          "useDefineForClassFields": true,
          "module": "ESNext",
          "lib": ["ES2020", "DOM", "DOM.Iterable"],
          "skipLibCheck": true,
          "moduleResolution": "bundler",
          "allowImportingTsExtensions": true,
          "resolveJsonModule": true,
          "isolatedModules": true,
          "moduleDetection": "force",
          "noEmit": true,
          "jsx": "react-jsx",
          "strict": true,
          "noUnusedLocals": true,
          "noUnusedParameters": true,
          "noFallthroughCasesInSwitch": true,
          "noUncheckedSideEffectImports": true
        },
        "include": ["js/**/*", "#{types_dir}/**/*"]
      }
      """

      Igniter.create_new_file(igniter, tsconfig_path, tsconfig_content, on_exists: :skip)
    end

    defp add_type_generation_alias(igniter) do
      igniter
      |> Igniter.Project.TaskAliases.add_alias("ts.gen", ["nb_ts.gen.types"])
      |> Igniter.add_notice("""
      Added mix alias: mix ts.gen

      Run 'mix ts.gen' to generate TypeScript types from your serializers.
      """)
    end

    defp maybe_setup_watcher(igniter, output_dir) do
      if igniter.args.options[:watch_mode] do
        setup_file_watcher(igniter, output_dir)
      else
        igniter
      end
    end

    defp setup_file_watcher(igniter, output_dir) do
      # First, ensure file_system dependency is added
      igniter = Igniter.Project.Deps.add_dep(igniter, {:file_system, "~> 1.0"})

      # Get the app name and endpoint with error handling
      app_name = Igniter.Project.Application.app_name(igniter)

      case Igniter.Libs.Phoenix.select_endpoint(igniter) do
        {igniter, nil} ->
          Igniter.add_warning(
            igniter,
            "Could not find Phoenix endpoint. File watcher for automatic type generation was not configured. You can manually run 'mix nb_ts.gen.types' to generate types."
          )

        {igniter, endpoint} ->
          # Add the watcher configuration to dev.exs
          watcher_value =
            {:code,
             quote do
               [
                 "mix",
                 "nb_ts.gen.types",
                 "--output-dir",
                 unquote(output_dir),
                 cd: Path.expand("..", __DIR__)
               ]
             end}

          case Igniter.Project.Config.configure(
                 igniter,
                 "dev.exs",
                 app_name,
                 [endpoint, :watchers, :nb_ts],
                 watcher_value
               ) do
            {:error, igniter} ->
              Igniter.add_warning(
                igniter,
                "Could not configure file watcher in dev.exs. You can manually run 'mix nb_ts.gen.types' to generate types."
              )

            result ->
              Igniter.add_notice(result, """
              Configured file watcher for automatic type generation.

              TypeScript types will be regenerated automatically when serializers change.
              The watcher runs 'mix nb_ts.gen.types' on file changes.
              """)
          end
      end
    end

    defp create_example_file(igniter) do
      # Find the web module to place the example in the right location
      web_module = Igniter.Libs.Phoenix.web_module(igniter)

      # Extract the base app name from web module (e.g., MyAppWeb -> MyApp)
      app_module_parts =
        case web_module do
          nil ->
            # Fallback to app name if web module not found
            [Igniter.Project.Application.app_name(igniter) |> to_string() |> Macro.camelize()]

          module ->
            module
            |> Module.split()
            |> Enum.take(1)
        end

      app_module = Module.concat(app_module_parts)

      example_module = Module.concat([app_module, "Examples", "TypeScriptExample"])

      example_content = """
      defmodule #{inspect(example_module)} do
        @moduledoc \"\"\"
        Example demonstrating NbTs usage with the ~TS sigil and type generation.

        This module shows how to:
        1. Use the ~TS sigil for compile-time TypeScript validation
        2. Define serializers that generate TypeScript interfaces
        3. Import and use generated types in your frontend code

        ## Type Generation

        To generate TypeScript types from your serializers, run:

            mix nb_ts.gen.types

        Or use the alias:

            mix ts.gen

        ## Using Generated Types

        In your TypeScript/JavaScript code:

        ```typescript
        import type { User, Post } from "@/types";

        // Use the generated types for type safety
        const user: User = {
          id: 1,
          name: "John Doe",
          email: "john@example.com"
        };

        const post: Post = {
          id: 1,
          title: "Hello World",
          body: "This is a post",
          author: user
        };
        ```

        ## Using the ~TS Sigil

        The ~TS sigil validates TypeScript syntax at compile time:

        ```elixir
        import NbTs.Sigil

        # Valid TypeScript types
        type = ~TS"string"
        type = ~TS"number | null"
        type = ~TS"{ id: number; name: string }"
        type = ~TS"Array<User>"

        # This will fail at compile time:
        # type = ~TS"{ invalid syntax"
        ```

        You can use the ~TS sigil in Inertia page props:

        ```elixir
        import NbTs.Sigil

        defmodule MyAppWeb.UserController do
          use MyAppWeb, :controller
          use Inertia.Controller

          inertia_page :index do
            prop :users, type: ~TS"Array<User>"
            prop :total, type: ~TS"number"
            prop :filters, type: ~TS"{ search?: string; status?: 'active' | 'inactive' }"
          end

          def index(conn, params) do
            users = Accounts.list_users(params)

            conn
            |> assign_prop(:users, users)
            |> assign_prop(:total, length(users))
            |> assign_prop(:filters, Map.take(params, ["search", "status"]))
            |> render_inertia("Users/Index")
          end
        end
        ```
        \"\"\"

        # This is just a documentation module - no implementation needed
      end
      """

      example_path =
        example_module
        |> Module.split()
        |> Enum.map(&Macro.underscore/1)
        |> Path.join()
        |> then(&"lib/#{&1}.ex")

      igniter
      |> Igniter.create_new_file(example_path, example_content, on_exists: :skip)
      |> Igniter.add_notice("""
      Created example file at #{example_path}

      This file demonstrates:
      - How to use the ~TS sigil for TypeScript validation
      - How to import and use generated types
      - How to use types with Inertia page props
      """)
    end

    defp add_initial_type_generation_task(igniter) do
      output_dir = igniter.args.options[:output_dir] || "assets/js/types"

      # Add a task to run after installation
      igniter
      |> Igniter.add_task("nb_ts.gen.types", [
        "--output-dir",
        output_dir
      ])
      |> Igniter.add_notice("""
      Initial type generation will run after installation.

      This will discover your NbSerializer serializers and generate TypeScript interfaces.
      """)
    end

    defp print_usage_instructions(igniter, output_dir) do
      watch_status = if igniter.args.options[:watch_mode], do: "enabled", else: "not enabled"

      Igniter.add_notice(igniter, """
      NbTs has been successfully installed!

      Configuration:
      - Output directory: #{output_dir}
      - File watcher: #{watch_status}
      - Mix alias: mix ts.gen

      Next steps:

      1. Import the ~TS sigil in modules where you need TypeScript validation:

         import NbTs.Sigil

      2. Use the ~TS sigil for compile-time type checking:

         prop :user, type: ~TS"{ id: number; name: string }"
         prop :status, type: ~TS"'active' | 'inactive'"

      3. Generate TypeScript types from your serializers:

         mix ts.gen

      4. Import generated types in your frontend code:

         import type { User, Post } from "@/types";

      5. For Inertia.js integration, use the ~TS sigil in page props:

         inertia_page :index do
           prop :users, type: ~TS"Array<User>"
         end

      Documentation:
      - NbTs: https://hexdocs.pm/nb_ts
      - NbSerializer: https://hexdocs.pm/nb_serializer

      #{if !igniter.args.options[:watch_mode] do
        """

        Tip: Run with --watch-mode to automatically regenerate types when serializers change:

          mix nb_ts.install --watch-mode
        """
      else
        ""
      end}
      """)
    end
  end
else
  # Fallback if Igniter is not installed
  defmodule Mix.Tasks.NbTs.Install do
    @shortdoc "Installs NbTs | Install `igniter` to use"
    @moduledoc """
    The task 'nb_ts.install' requires igniter for advanced installation features.

    To use the full installer with automatic configuration, install igniter:

        {:igniter, "~> 0.5", only: [:dev]}

    Then run:

        mix deps.get
        mix nb_ts.install

    ## Manual Installation

    If you prefer not to use Igniter, you can manually:

    1. Add nb_ts to your mix.exs dependencies:

        {:nb_ts, "~> 0.1"}

    2. Run mix deps.get

    3. Create the output directory:

        mkdir -p assets/js/types

    4. Add a mix alias in mix.exs:

        def project do
          [
            aliases: aliases()
          ]
        end

        defp aliases do
          [
            "ts.gen": ["nb_ts.gen.types"]
          ]
        end

    5. Import the ~TS sigil where needed:

        import NbTs.Sigil

    6. Generate types:

        mix nb_ts.gen.types
    """

    use Mix.Task

    def run(_argv) do
      Mix.shell().info("""
      The task 'nb_ts.install' requires igniter for automatic installation.

      To install igniter, add it to your mix.exs:

          {:igniter, "~> 0.5", only: [:dev]}

      Then run:

          mix deps.get
          mix nb_ts.install

      Or see the manual installation instructions above.
      """)
    end
  end
end
