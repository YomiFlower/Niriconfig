return {
  {
    "sainnhe/everforest",
    name = "everforest",
    priority = 1000, -- Ensures it loads first
    config = function()
      vim.g.everforest_background = "hard" -- Options: 'hard', 'medium', 'soft'
      vim.g.everforest_transparent_background = 1 -- Transparent background
      vim.g.everforest_enable_italic = 1 -- Italic comments
      vim.cmd.colorscheme("everforest") -- Set colorscheme
    end,
  },
}
