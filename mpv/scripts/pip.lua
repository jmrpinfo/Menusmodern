local opt = require "mp.options"

local opts = {
    -- mini player no canto inferior direito
    geometry = "520x293-25-80",

    -- centro da tela ao sair do mini player
    restore_geometry = "50%:50%",

    auto = false,
}

opt.read_options(opts, "pip")

local pip = false
local saved = {}

local function center_window()
    -- centraliza mais de uma vez para evitar atraso do resize/borda no Windows
    mp.add_timeout(0.05, function()
        mp.set_property("geometry", opts.restore_geometry)
    end)

    mp.add_timeout(0.15, function()
        mp.set_property("geometry", opts.restore_geometry)
    end)
end

local function enter_pip()
    if pip then return end

    saved.fullscreen = mp.get_property_native("fullscreen")
    saved.maximized = mp.get_property_native("window-maximized")
    saved.border = mp.get_property_native("border")
    saved.ontop = mp.get_property_native("ontop")

    -- salva o tamanho/escala real atual antes de virar mini player
    saved.window_scale =
        mp.get_property_number("current-window-scale") or
        mp.get_property_number("window-scale") or
        1

    mp.set_property_native("fullscreen", false)
    mp.set_property_native("window-maximized", false)
    mp.set_property_native("border", false)
    mp.set_property_native("ontop", true)
    mp.set_property("geometry", opts.geometry)

    pip = true
    mp.osd_message("Mini player")
end

local function leave_pip()
    if not pip then return end

    mp.set_property_native("ontop", saved.ontop or false)
    mp.set_property_native("border", saved.border ~= false)
    mp.set_property_native("window-maximized", false)
    mp.set_property_native("fullscreen", false)

    -- restaura a escala que a janela tinha antes do mini player
    if saved.window_scale then
        mp.set_property_number("window-scale", saved.window_scale)
    end

    center_window()

    if saved.fullscreen then
        mp.add_timeout(0.2, function()
            mp.set_property_native("fullscreen", true)
        end)
    end

    pip = false
    mp.osd_message("Janela normal")
end

local function toggle_pip()
    if pip then
        leave_pip()
    else
        enter_pip()
    end
end

mp.add_key_binding(nil, "toggle-pip", toggle_pip)
mp.add_forced_key_binding("ctrl+p", "toggle-pip-ctrl-p", toggle_pip)
mp.register_script_message("toggle", toggle_pip)

if opts.auto then
    mp.observe_property("focused", "bool", function(_, focused)
        if focused == false then
            enter_pip()
        elseif focused == true then
            leave_pip()
        end
    end)
end