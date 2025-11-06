defmodule NbTs.FormGenerationTest do
  use ExUnit.Case, async: false

  alias NbTs.Interface

  @test_dir "tmp/test_form_generation"

  setup do
    # Clean and create test directory
    File.rm_rf!(@test_dir)
    File.mkdir_p!(@test_dir)

    # Start dependencies (if not already started)
    start_supervised({NbTs.Registry, []}, restart: :temporary)
    start_supervised({NbTs.DependencyTracker, []}, restart: :temporary)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
    end)

    {:ok, output_dir: @test_dir}
  end

  describe "generate_page_interface/4 with form inputs" do
    test "generates FormInputs interface for page with single form" do
      defmodule SimpleFormController do
        def __inertia_pages__ do
          %{
            users_new: %{
              component: "Users/New",
              props: []
            }
          }
        end

        def __inertia_forms__ do
          %{
            user: [
              {:name, :string, []},
              {:email, :string, []}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = SimpleFormController.__inertia_forms__()

      page_config = %{
        component: "Users/New",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:users_new, page_config, [], [])

      # Should have UsersNewProps interface
      assert typescript =~ "export interface UsersNewProps"

      # Should have UsersNewFormInputs interface
      assert typescript =~ "export interface UsersNewFormInputs"

      # Should have user form with name and email fields
      assert typescript =~ "user:"
      assert typescript =~ "name: string;"
      assert typescript =~ "email: string;"
    end

    test "generates optional fields with ? syntax" do
      defmodule OptionalFieldsController do
        def __inertia_pages__ do
          %{
            users_edit: %{
              component: "Users/Edit",
              props: []
            }
          }
        end

        def __inertia_forms__ do
          %{
            user: [
              {:name, :string, []},
              {:age, :integer, [optional: true]},
              {:bio, :string, [optional: true]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = OptionalFieldsController.__inertia_forms__()

      page_config = %{
        component: "Users/Edit",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:users_edit, page_config, [], [])

      # Required field should not have ?
      assert typescript =~ ~r/name:\s*string;/

      # Optional fields should have ?
      assert typescript =~ ~r/age\?:\s*number;/
      assert typescript =~ ~r/bio\?:\s*string;/
    end

    test "generates multiple forms in FormInputs interface" do
      defmodule MultipleFormsController do
        def __inertia_pages__ do
          %{
            settings: %{
              component: "Settings/Index",
              props: []
            }
          }
        end

        def __inertia_forms__ do
          %{
            profile: [
              {:name, :string, []}
            ],
            password: [
              {:current_password, :string, []},
              {:new_password, :string, []}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = MultipleFormsController.__inertia_forms__()

      page_config = %{
        component: "Settings/Index",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:settings, page_config, [], [])

      # Should have both forms
      assert typescript =~ "profile:"
      assert typescript =~ "password:"
      assert typescript =~ "currentPassword: string;"
      assert typescript =~ "newPassword: string;"
    end

    test "maps all type correctly" do
      defmodule AllTypesController do
        def __inertia_pages__ do
          %{
            types_test: %{
              component: "TypesTest",
              props: []
            }
          }
        end

        def __inertia_forms__ do
          %{
            data: [
              {:str_field, :string, []},
              {:num_field, :number, []},
              {:int_field, :integer, []},
              {:bool_field, :boolean, []},
              {:any_field, :any, []},
              {:date_field, :date, []},
              {:datetime_field, :datetime, []},
              {:map_field, :map, []}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = AllTypesController.__inertia_forms__()

      page_config = %{
        component: "TypesTest",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:types_test, page_config, [], [])

      # Check type mappings
      assert typescript =~ ~r/strField:\s*string;/
      assert typescript =~ ~r/numField:\s*number;/
      assert typescript =~ ~r/intField:\s*number;/
      assert typescript =~ ~r/boolField:\s*boolean;/
      assert typescript =~ ~r/anyField:\s*any;/
      # ISO format
      assert typescript =~ ~r/dateField:\s*string;/
      # ISO format
      assert typescript =~ ~r/datetimeField:\s*string;/
      assert typescript =~ ~r/mapField:\s*Record<string, any>;/
    end

    test "handles page with no forms" do
      defmodule NoFormsController do
        def __inertia_pages__ do
          %{
            dashboard: %{
              component: "Dashboard",
              props: [%{name: :data, type: :string, opts: []}]
            }
          }
        end

        def __inertia_forms__, do: %{}

        def __inertia_shared_modules__, do: []
      end

      page_config = %{
        component: "Dashboard",
        props: [%{name: :data, type: :string, opts: []}]
      }

      typescript = Interface.generate_page_interface(:dashboard, page_config, [], [])

      # Should have DashboardProps
      assert typescript =~ "export interface DashboardProps"

      # Should NOT have FormInputs interface when no forms
      refute typescript =~ "FormInputs"
    end

    test "camelizes field names" do
      defmodule CamelizeController do
        def __inertia_pages__ do
          %{
            test: %{
              component: "Test",
              props: []
            }
          }
        end

        def __inertia_forms__ do
          %{
            data: [
              {:first_name, :string, []},
              {:last_name, :string, []},
              {:date_of_birth, :date, []}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = CamelizeController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Should camelCase field names
      assert typescript =~ "firstName:"
      assert typescript =~ "lastName:"
      assert typescript =~ "dateOfBirth:"
    end

    test "camelizes form names" do
      defmodule CamelizeFormNameController do
        def __inertia_pages__ do
          %{
            test: %{
              component: "Test",
              props: []
            }
          }
        end

        def __inertia_forms__ do
          %{
            user_profile: [
              {:name, :string, []}
            ],
            shipping_address: [
              {:street, :string, []}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = CamelizeFormNameController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Should camelCase form names
      assert typescript =~ "userProfile:"
      assert typescript =~ "shippingAddress:"
    end
  end

  describe "generate_page_types/2 integration with forms" do
    test "generates types for controller with forms" do
      defmodule IntegrationController do
        def __inertia_pages__ do
          %{
            users_new: %{
              component: "Users/New",
              props: []
            }
          }
        end

        def __inertia_forms__ do
          %{
            user: [
              {:name, :string, []},
              {:email, :string, []}
            ]
          }
        end

        def inertia_shared_props, do: []
        def __inertia_shared_modules__, do: []
      end

      typescript = Interface.generate_page_types(IntegrationController)

      assert typescript =~ "UsersNewProps"
      assert typescript =~ "UsersNewFormInputs"
      assert typescript =~ "user:"
    end

    test "generates separate files for pages with forms using as_list: true" do
      defmodule MultiPageController do
        def __inertia_pages__ do
          %{
            users_new: %{
              component: "Users/New",
              props: []
            },
            users_edit: %{
              component: "Users/Edit",
              props: []
            }
          }
        end

        def __inertia_forms__ do
          %{
            user: [
              {:name, :string, []}
            ]
          }
        end

        def inertia_shared_props, do: []
        def __inertia_shared_modules__, do: []
      end

      pages = Interface.generate_page_types(MultiPageController, as_list: true)

      assert length(pages) == 2

      # Each page should have its TypeScript
      Enum.each(pages, fn {_page_name, _config, typescript} ->
        assert typescript =~ "Props"
        assert typescript =~ "FormInputs"
      end)
    end
  end

  describe "full integration with NbTs.Generator" do
    test "generates complete TypeScript files with forms", %{output_dir: dir} do
      defmodule FullIntegrationController do
        def __inertia_pages__ do
          %{
            users_create: %{
              component: "Users/Create",
              props: [%{name: :roles, type: :list, opts: []}]
            }
          }
        end

        def __inertia_forms__ do
          %{
            user: [
              {:name, :string, []},
              {:email, :string, []},
              {:admin, :boolean, [optional: true]}
            ]
          }
        end

        def inertia_page_config(:users_create) do
          %{
            component: "Users/Create",
            props: [%{name: :roles, type: :list, opts: []}]
          }
        end

        def inertia_shared_props, do: []
        def __inertia_shared_modules__, do: []
      end

      {:ok, _results} =
        NbTs.Generator.generate_incremental(
          serializers: [],
          controllers: [FullIntegrationController],
          shared_props: [],
          output_dir: dir
        )

      filepath = Path.join(dir, "UsersCreateProps.ts")
      assert File.exists?(filepath)

      content = File.read!(filepath)

      # Should have Props interface
      assert content =~ "export interface UsersCreateProps"
      assert content =~ "roles:"

      # Should have FormInputs interface
      assert content =~ "export interface UsersCreateFormInputs"
      assert content =~ "user:"
      assert content =~ "name: string;"
      assert content =~ "email: string;"
      assert content =~ "admin?: boolean;"
    end

    test "validates generated TypeScript with forms", %{output_dir: dir} do
      defmodule ValidationController do
        def __inertia_pages__ do
          %{
            test: %{
              component: "Test",
              props: []
            }
          }
        end

        def __inertia_forms__ do
          %{
            data: [
              {:field, :string, []}
            ]
          }
        end

        def inertia_page_config(:test) do
          %{
            component: "Test",
            props: []
          }
        end

        def inertia_shared_props, do: []
        def __inertia_shared_modules__, do: []
      end

      # Generate with validation enabled
      assert {:ok, _results} =
               NbTs.Generator.generate_incremental(
                 serializers: [],
                 controllers: [ValidationController],
                 shared_props: [],
                 output_dir: dir,
                 validate: true
               )

      # Should succeed - TypeScript is valid
      filepath = Path.join(dir, "TestProps.ts")
      assert File.exists?(filepath)
    end
  end

  describe "edge cases" do
    test "handles controller without __inertia_forms__ function" do
      defmodule NoFormsFunction do
        def __inertia_pages__ do
          %{
            test: %{
              component: "Test",
              props: []
            }
          }
        end

        def __inertia_shared_modules__, do: []
      end

      page_config = %{
        component: "Test",
        props: []
      }

      # Should not crash
      typescript = Interface.generate_page_interface(:test, page_config, [], [])
      assert typescript =~ "TestProps"
      refute typescript =~ "FormInputs"
    end

    test "handles empty forms map" do
      defmodule EmptyForms do
        def __inertia_pages__ do
          %{
            test: %{
              component: "Test",
              props: []
            }
          }
        end

        def __inertia_forms__, do: %{}
        def __inertia_shared_modules__, do: []
      end

      page_config = %{
        component: "Test",
        props: []
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])
      assert typescript =~ "TestProps"
      refute typescript =~ "FormInputs"
    end

    test "handles form with single field" do
      defmodule SingleFieldForm do
        def __inertia_pages__ do
          %{
            test: %{
              component: "Test",
              props: []
            }
          }
        end

        def __inertia_forms__ do
          %{
            simple: [
              {:value, :string, []}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = SingleFieldForm.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])
      assert typescript =~ "TestFormInputs"
      assert typescript =~ "simple:"
      assert typescript =~ "value: string;"
    end
  end

  describe "type mapping edge cases" do
    test "handles unknown type with fallback" do
      defmodule UnknownTypeController do
        def __inertia_pages__ do
          %{
            test: %{
              component: "Test",
              props: []
            }
          }
        end

        def __inertia_forms__ do
          %{
            data: [
              {:weird_field, :unknown_type, []}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = UnknownTypeController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Unknown types should default to 'any'
      assert typescript =~ ~r/weirdField:\s*any;/
    end

    test "adds comments for date/datetime types" do
      defmodule DateCommentsController do
        def __inertia_pages__ do
          %{
            test: %{
              component: "Test",
              props: []
            }
          }
        end

        def __inertia_forms__ do
          %{
            data: [
              {:created_at, :datetime, []},
              {:birth_date, :date, []}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = DateCommentsController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Should have string type for dates
      assert typescript =~ ~r/createdAt:\s*string;/
      assert typescript =~ ~r/birthDate:\s*string;/

      # Ideally should have comments (optional enhancement)
      # assert typescript =~ "ISO"
    end
  end
end
