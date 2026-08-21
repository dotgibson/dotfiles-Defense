-- ================================================================================================
-- TITLE : SchemaStore.nvim | JSON & YAML schema catalogue for the language servers
-- LINKS : https://github.com/b0o/SchemaStore.nvim
-- ABOUT : A data-only plugin (no setup, no runtime cost) that bundles the schemastore.org catalogue.
--         It's what gives jsonls / yamlls real validation + completion for the hundreds of common
--         config files — package.json, tsconfig.json, .eslintrc, GitHub Actions workflows,
--         docker-compose, kubernetes manifests, .gitlab-ci, renovate, and so on — instead of the
--         two hand-listed schemas yamlls carried and the zero jsonls had.
-- WIRED IN: servers/jsonls.lua and servers/yamlls.lua call require("schemastore").json/yaml.schemas().
-- LAZY  : lazy = true — it ships only Lua tables, loaded the moment a server config requires it.
-- ================================================================================================
return {
	"b0o/schemastore.nvim",
	lazy = true,
}
