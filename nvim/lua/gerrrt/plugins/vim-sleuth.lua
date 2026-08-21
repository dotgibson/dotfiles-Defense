-- ================================================================================================
-- TITLE : vim-sleuth | auto-detect indentation per file
-- LINKS : https://github.com/tpope/vim-sleuth
-- ABOUT : Your options.lua sets a sensible default (2-space, expandtab) and .editorconfig pins it
--         for files INSIDE this repo — but when you open someone else's project that uses tabs or
--         4-space and ships no .editorconfig, those defaults are wrong. Sleuth heuristically reads
--         the surrounding file/project and sets shiftwidth/expandtab to match, so edits stay
--         consistent with the file you're in. It defers to .editorconfig, so it never fights it.
-- LAZY  : loads on first file read; zero config (tpope plugins are intentionally option-free).
-- ================================================================================================
return {
	"tpope/vim-sleuth",
	event = { "BufReadPost", "BufNewFile" },
}
