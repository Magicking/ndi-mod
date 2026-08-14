local mod = require 'core/mods'

local this_name = mod.this_name

mod.hook.register("system_post_startup", "ndi-system-post-startup", function()
  package.cpath = package.cpath .. ";" .. paths.code .. this_name .. "/lib/?.so"
  ndi_mod = require 'ndi_mod'

  local started = false

  -- Hook the single low-level screen-flip primitive (_norns.screen_update)
  -- instead of screen.update_default(). screen.update_default is only
  -- reached via screen.update(), which user scripts call -- but system
  -- menu pages (SYSTEM, MIX, TAPE, RESTART, SLEEP, DEVICES, MODS, PREVIEW,
  -- SELECT, ...) and the low-battery screen also call screen.update(), and
  -- most of them only redraw on key/encoder input rather than through a
  -- script's redraw loop. Every one of those paths bottoms out in
  -- _norns.screen_update(), so patching it here keeps NDI live whenever
  -- anything hits the screen, script or no script, instead of needing a
  -- separate patch per menu page.
  local original_screen_update = _norns.screen_update
  _norns.screen_update = function()
    if not started then
      -- clients get confused if norns starts up NDI too quickly
      -- after a restart, so delay init until the first screen update
      started = true
      ndi_mod.init()
      ndi_mod.init_audio()
      ndi_mod.start()
    end
    original_screen_update()
    ndi_mod.update()
  end

  -- the screensaver deliberately stops calling _norns.screen_update() once
  -- active (to avoid needless LCD writes while dimmed), bypassing the hook
  -- above entirely -- patch its metro event handler separately so NDI
  -- streaming continues while it's active.
  local original_ss_event = metro[36].event
  metro[36].event = function()
    original_ss_event()
    screen.update = function()
      ndi_mod.update()
    end
  end
end)

mod.hook.register("system_pre_shutdown", "ndi-system-pre-shutdown", function()
  ndi_mod.cleanup_audio()
  ndi_mod.cleanup()
end)

mod.hook.register("script_post_init", "ndi-script-post-init", function()
  local script_refresh_fn = norns.script.refresh
  norns.script.refresh = function()
    ndi_mod.update()
    script_refresh_fn()
  end
end)
