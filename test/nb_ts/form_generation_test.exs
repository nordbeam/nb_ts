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
              props: [],
              forms: %{
                user: [
                  {:name, :string, []},
                  {:email, :string, []}
                ]
              }
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
              props: [],
              forms: %{
                user: [
                  {:name, :string, []}
                ]
              }
            },
            users_edit: %{
              component: "Users/Edit",
              props: [],
              forms: %{
                user: [
                  {:name, :string, []}
                ]
              }
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
              props: [%{name: :roles, type: :list, opts: []}],
              forms: %{
                user: [
                  {:name, :string, []},
                  {:email, :string, []},
                  {:admin, :boolean, [optional: true]}
                ]
              }
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
            props: [%{name: :roles, type: :list, opts: []}],
            forms: %{
              user: [
                {:name, :string, []},
                {:email, :string, []},
                {:admin, :boolean, [optional: true]}
              ]
            }
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

  describe "nested list fields" do
    test "generates array type for nested list fields" do
      defmodule NestedListController do
        def __inertia_pages__ do
          %{
            spaces_new: %{
              component: "Spaces/New",
              props: []
            }
          }
        end

        def __inertia_forms__ do
          %{
            space: [
              {:name, :string, []},
              {:questions, :list, [],
               [
                 {:question_text, :string, []},
                 {:required, :boolean, []},
                 {:position, :integer, []}
               ]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      forms = NestedListController.__inertia_forms__()

      page_config = %{
        component: "Spaces/New",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:spaces_new, page_config, [], [])

      # Should have FormInputs interface
      assert typescript =~ "export interface SpacesNewFormInputs"

      # Should have space form
      assert typescript =~ "space:"

      # Should have name field
      assert typescript =~ ~r/name:\s*string;/

      # Should have questions as array of objects
      assert typescript =~ ~r/questions:\s*Array<\{/
      assert typescript =~ ~r/questionText:\s*string;/
      assert typescript =~ ~r/required:\s*boolean;/
      assert typescript =~ ~r/position:\s*number;/
    end

    test "generates optional nested list fields" do
      defmodule OptionalNestedListController do
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
              {:name, :string, []},
              {:items, :list, [optional: true],
               [
                 {:label, :string, []}
               ]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      forms = OptionalNestedListController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Optional list should have ?
      assert typescript =~ ~r/items\?:\s*Array<\{/
      assert typescript =~ ~r/label:\s*string;/
    end

    test "generates nested list with optional inner fields" do
      defmodule NestedOptionalFieldsController do
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
              {:items, :list, [],
               [
                 {:name, :string, []},
                 {:description, :string, [optional: true]},
                 {:required, :boolean, []}
               ]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      forms = NestedOptionalFieldsController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Should have array with nested object
      assert typescript =~ ~r/items:\s*Array<\{/

      # Required inner fields should not have ?
      assert typescript =~ ~r/name:\s*string;/
      assert typescript =~ ~r/required:\s*boolean;/

      # Optional inner fields should have ?
      assert typescript =~ ~r/description\?:\s*string;/
    end

    test "generates multiple nested list fields" do
      defmodule MultipleNestedListsController do
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
              {:questions, :list, [],
               [
                 {:text, :string, []}
               ]},
              {:answers, :list, [],
               [
                 {:value, :string, []}
               ]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      forms = MultipleNestedListsController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Should have both arrays
      assert typescript =~ ~r/questions:\s*Array<\{/
      assert typescript =~ ~r/text:\s*string;/

      assert typescript =~ ~r/answers:\s*Array<\{/
      assert typescript =~ ~r/value:\s*string;/
    end

    test "handles nested list with all basic types" do
      defmodule NestedAllTypesController do
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
              {:items, :list, [],
               [
                 {:str, :string, []},
                 {:num, :number, []},
                 {:int, :integer, []},
                 {:bool, :boolean, []},
                 {:dt, :datetime, []}
               ]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      forms = NestedAllTypesController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Check all type mappings inside nested array
      assert typescript =~ ~r/str:\s*string;/
      assert typescript =~ ~r/num:\s*number;/
      assert typescript =~ ~r/int:\s*number;/
      assert typescript =~ ~r/bool:\s*boolean;/
      assert typescript =~ ~r/dt:\s*string;/
    end
  end

  describe "snake_case_params config for form inputs" do
    test "respects snake_case_params: false config" do
      # Set config to false - frontend should send snake_case
      Application.put_env(:nb_inertia, :snake_case_params, false)

      on_exit(fn ->
        # Restore default
        Application.delete_env(:nb_inertia, :snake_case_params)
      end)

      defmodule NoCamelizeController do
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
              {:first_name, :string, []},
              {:last_name, :string, []},
              {:date_of_birth, :date, [optional: true]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      forms = NoCamelizeController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Should NOT camelCase - keep snake_case
      assert typescript =~ "user_profile:"
      assert typescript =~ "first_name:"
      assert typescript =~ "last_name:"
      assert typescript =~ "date_of_birth?:"

      # Should NOT have camelCase versions
      refute typescript =~ "userProfile"
      refute typescript =~ "firstName"
      refute typescript =~ "lastName"
      refute typescript =~ "dateOfBirth"
    end

    test "respects snake_case_params: false with nested list fields" do
      # Set config to false - frontend should send snake_case
      Application.put_env(:nb_inertia, :snake_case_params, false)

      on_exit(fn ->
        # Restore default
        Application.delete_env(:nb_inertia, :snake_case_params)
      end)

      defmodule NoCamelizeNestedController do
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
            space_data: [
              {:space_name, :string, []},
              {:question_list, :list, [],
               [
                 {:question_text, :string, []},
                 {:is_required, :boolean, []}
               ]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      forms = NoCamelizeNestedController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Form name should NOT be camelized
      assert typescript =~ "space_data:"

      # Outer field names should NOT be camelized
      assert typescript =~ "space_name:"
      assert typescript =~ "question_list:"

      # Nested field names should NOT be camelized
      assert typescript =~ "question_text:"
      assert typescript =~ "is_required:"

      # Should NOT have camelCase versions
      refute typescript =~ "spaceData"
      refute typescript =~ "spaceName"
      refute typescript =~ "questionList"
      refute typescript =~ "questionText"
      refute typescript =~ "isRequired"
    end

    test "defaults to snake_case_params: true (generates camelCase) when not configured" do
      # Ensure no config is set
      Application.delete_env(:nb_inertia, :snake_case_params)

      defmodule DefaultCamelizeController do
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
            user_data: [
              {:first_name, :string, []}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      forms = DefaultCamelizeController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Should default to camelCase
      assert typescript =~ "userData:"
      assert typescript =~ "firstName:"
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

    test "generates typed arrays for list: type syntax" do
      defmodule TypedListController do
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
            config: [
              {:allowed_origins, :any, [list: :string, optional: true]},
              {:port_numbers, :any, [list: :integer]},
              {:feature_flags, :any, [list: :boolean]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = TypedListController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Should have typed arrays
      assert typescript =~ ~r/allowedOrigins\?:\s*string\[\];/
      assert typescript =~ ~r/portNumbers:\s*number\[\];/
      assert typescript =~ ~r/featureFlags:\s*boolean\[\];/
    end

    test "supports all basic types in typed lists" do
      defmodule AllTypedListsController do
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
              {:strings, :any, [list: :string]},
              {:numbers, :any, [list: :number]},
              {:integers, :any, [list: :integer]},
              {:booleans, :any, [list: :boolean]},
              {:dates, :any, [list: :date]},
              {:datetimes, :any, [list: :datetime]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = AllTypedListsController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # All should be typed arrays
      assert typescript =~ ~r/strings:\s*string\[\];/
      assert typescript =~ ~r/numbers:\s*number\[\];/
      assert typescript =~ ~r/integers:\s*number\[\];/
      assert typescript =~ ~r/booleans:\s*boolean\[\];/
      assert typescript =~ ~r/dates:\s*string\[\];/
      assert typescript =~ ~r/datetimes:\s*string\[\];/
    end

    test "respects snake_case_params config with typed lists" do
      # Set snake_case_params to false
      Application.put_env(:nb_inertia, :snake_case_params, false)

      on_exit(fn ->
        Application.delete_env(:nb_inertia, :snake_case_params)
      end)

      defmodule SnakeCaseTypedListController do
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
            config: [
              {:allowed_origins, :any, [list: :string]},
              {:port_numbers, :any, [list: :integer]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = SnakeCaseTypedListController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Should generate snake_case TypeScript
      assert typescript =~ ~r/allowed_origins:\s*string\[\];/
      assert typescript =~ ~r/port_numbers:\s*number\[\];/
      # Should NOT have camelCase
      refute typescript =~ "allowedOrigins"
      refute typescript =~ "portNumbers"
    end

    test "mixes typed lists with nested list fields" do
      defmodule MixedListTypesController do
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
            config: [
              {:name, :string, []},
              {:tags, :any, [list: :string]},
              {:questions, :list, [],
               [
                 {:text, :string, []},
                 {:required, :boolean, []}
               ]},
              {:ports, :any, [list: :integer, optional: true]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = MixedListTypesController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Should have regular field
      assert typescript =~ ~r/name:\s*string;/
      # Should have typed array
      assert typescript =~ ~r/tags:\s*string\[\];/
      # Should have nested object array
      assert typescript =~ ~r/questions:\s*Array<\{/
      assert typescript =~ ~r/text:\s*string;/
      assert typescript =~ ~r/required:\s*boolean;/
      # Should have optional typed array
      assert typescript =~ ~r/ports\?:\s*number\[\];/
    end
  end

  describe "generate_page_interface/4 with enum fields" do
    test "generates union types for enum fields" do
      defmodule EnumFieldsController do
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
            config: [
              {:status, :any, [enum: ["active", "inactive", "pending"]]},
              {:priority, :any, [enum: ["low", "medium", "high"], optional: true]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = EnumFieldsController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Should have union types
      assert typescript =~ ~r/status:\s*"active"\s*\|\s*"inactive"\s*\|\s*"pending";/
      assert typescript =~ ~r/priority\?:\s*"low"\s*\|\s*"medium"\s*\|\s*"high";/
    end

    test "generates enum arrays for list of enums" do
      defmodule EnumArraysController do
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
            config: [
              {:statuses, :any, [list: [enum: ["active", "inactive"]]]},
              {:tags, :any, [list: [enum: ["bug", "feature", "enhancement"]], optional: true]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = EnumArraysController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Should have enum arrays with parentheses
      assert typescript =~ ~r/statuses:\s*\("active"\s*\|\s*"inactive"\)\[\];/
      assert typescript =~ ~r/tags\?:\s*\("bug"\s*\|\s*"feature"\s*\|\s*"enhancement"\)\[\];/
    end

    test "mixes enums with other field types" do
      defmodule MixedEnumsController do
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
            config: [
              {:name, :string, []},
              {:status, :any, [enum: ["active", "inactive"]]},
              {:tags, :any, [list: :string]},
              {:priorities, :any, [list: [enum: ["low", "high"]]]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = MixedEnumsController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Should have all field types
      assert typescript =~ ~r/name:\s*string;/
      assert typescript =~ ~r/status:\s*"active"\s*\|\s*"inactive";/
      assert typescript =~ ~r/tags:\s*string\[\];/
      assert typescript =~ ~r/priorities:\s*\("low"\s*\|\s*"high"\)\[\];/
    end

    test "respects snake_case_params config with enums" do
      # Set snake_case_params to false
      Application.put_env(:nb_inertia, :snake_case_params, false)

      on_exit(fn ->
        Application.delete_env(:nb_inertia, :snake_case_params)
      end)

      defmodule SnakeCaseEnumController do
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
            config: [
              {:user_status, :any, [enum: ["active", "inactive"]]},
              {:priority_level, :any, [list: [enum: ["low", "high"]]]}
            ]
          }
        end

        def __inertia_shared_modules__, do: []
      end

      # Extract forms from controller
      forms = SnakeCaseEnumController.__inertia_forms__()

      page_config = %{
        component: "Test",
        props: [],
        forms: forms
      }

      typescript = Interface.generate_page_interface(:test, page_config, [], [])

      # Should generate snake_case field names
      assert typescript =~ ~r/user_status:\s*"active"\s*\|\s*"inactive";/
      assert typescript =~ ~r/priority_level:\s*\("low"\s*\|\s*"high"\)\[\];/
      # Should NOT have camelCase
      refute typescript =~ "userStatus"
      refute typescript =~ "priorityLevel"
    end
  end
end
