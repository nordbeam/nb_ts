defmodule NbTs.ValidationBench do
  @moduledoc """
  Benchmarks for TypeScript validation performance using tsgo.

  Run with: mix run bench/validation_bench.exs
  """

  alias NbTs.TsgoValidator

  def run do
    IO.puts("\n=== NbTs Validation Benchmark ===\n")

    # Warm up the pool
    IO.puts("Warming up tsgo pool...")
    TsgoValidator.validate("{ id: number }")
    :timer.sleep(100)

    IO.puts("Running benchmarks...\n")

    # Simple types
    benchmark("Simple object type", fn ->
      TsgoValidator.validate("{ id: number; name: string }")
    end)

    benchmark("Primitive type", fn ->
      TsgoValidator.validate("string")
    end)

    benchmark("Array type", fn ->
      TsgoValidator.validate("Array<string>")
    end)

    benchmark("Union type", fn ->
      TsgoValidator.validate("'active' | 'inactive' | 'pending'")
    end)

    # Medium complexity
    benchmark("Medium complexity type", fn ->
      TsgoValidator.validate("""
      {
        id: number;
        name: string;
        email: string;
        metadata: Record<string, unknown>;
        status: 'active' | 'inactive';
      }
      """)
    end)

    # Complex types
    benchmark("Complex nested type", fn ->
      TsgoValidator.validate("""
      {
        user: {
          id: number;
          name: string;
          email: string;
          profile: {
            bio: string;
            avatar?: string;
            social: Record<string, string>;
          };
        };
        posts: Array<{
          id: number;
          title: string;
          tags: string[];
        }>;
        meta: {
          timestamp: number;
          version: string;
        };
      }
      """)
    end)

    # Very complex type
    benchmark("Very complex type (50 fields)", fn ->
      fields =
        for i <- 1..50 do
          "field#{i}: number | string | boolean"
        end
        |> Enum.join(";\n  ")

      TsgoValidator.validate("{\n  #{fields}\n}")
    end)

    # Utility types
    benchmark("Partial utility type", fn ->
      TsgoValidator.validate("Partial<{ name: string; age: number; email: string }>")
    end)

    benchmark("Pick utility type", fn ->
      TsgoValidator.validate("Pick<{ id: number; name: string; age: number }, 'id' | 'name'>")
    end)

    # Type errors (should still be fast)
    benchmark("Type error detection", fn ->
      TsgoValidator.validate("const x: number = 'string'")
    end)

    # Concurrency benchmark
    IO.puts("\n--- Concurrency Benchmark ---\n")
    benchmark_concurrent(10, "10 concurrent validations")
    benchmark_concurrent(20, "20 concurrent validations")
    benchmark_concurrent(50, "50 concurrent validations")
    benchmark_concurrent(100, "100 concurrent validations")

    # Throughput test
    IO.puts("\n--- Throughput Test ---\n")
    throughput_test(1000)

    IO.puts("\n=== Benchmark Complete ===\n")
  end

  defp benchmark(name, fun) do
    # Run 100 times and get average
    times =
      for _ <- 1..100 do
        {time_us, _result} = :timer.tc(fun)
        time_us
      end

    avg_us = Enum.sum(times) / length(times)
    avg_ms = avg_us / 1000
    min_ms = Enum.min(times) / 1000
    max_ms = Enum.max(times) / 1000
    p95_ms = percentile(times, 95) / 1000
    p99_ms = percentile(times, 99) / 1000

    IO.puts("#{name}:")
    IO.puts("  Average: #{Float.round(avg_ms, 2)}ms")
    IO.puts("  Min: #{Float.round(min_ms, 2)}ms")
    IO.puts("  Max: #{Float.round(max_ms, 2)}ms")
    IO.puts("  P95: #{Float.round(p95_ms, 2)}ms")
    IO.puts("  P99: #{Float.round(p99_ms, 2)}ms")
    IO.puts("")
  end

  defp benchmark_concurrent(count, name) do
    code = "{ id: number; name: string; email: string }"

    {time_us, results} =
      :timer.tc(fn ->
        tasks =
          for _ <- 1..count do
            Task.async(fn -> TsgoValidator.validate(code) end)
          end

        Task.await_many(tasks, 30_000)
      end)

    time_ms = time_us / 1000
    successes = Enum.count(results, &match?({:ok, _}, &1))
    avg_per_validation = time_ms / count

    IO.puts("#{name}:")
    IO.puts("  Total time: #{Float.round(time_ms, 2)}ms")
    IO.puts("  Per validation: #{Float.round(avg_per_validation, 2)}ms")
    IO.puts("  Successes: #{successes}/#{count}")
    IO.puts("")
  end

  defp throughput_test(count) do
    code = "{ id: number; name: string }"

    IO.puts("Validating #{count} types sequentially...")

    {time_us, results} =
      :timer.tc(fn ->
        for _ <- 1..count do
          TsgoValidator.validate(code)
        end
      end)

    time_s = time_us / 1_000_000
    successes = Enum.count(results, &match?({:ok, _}, &1))
    validations_per_sec = count / time_s

    IO.puts("  Total time: #{Float.round(time_s, 2)}s")
    IO.puts("  Successes: #{successes}/#{count}")
    IO.puts("  Throughput: #{Float.round(validations_per_sec, 0)} validations/second")
    IO.puts("")
  end

  defp percentile(list, p) do
    sorted = Enum.sort(list)
    index = ceil(length(sorted) * p / 100) - 1
    Enum.at(sorted, max(index, 0))
  end
end

# Run the benchmark
NbTs.ValidationBench.run()
