local mp = require "mp"
local assdraw = require "mp.assdraw"

local SCRIPT = "modernz_menus"
local INPUT_GROUP = "modernz_menus_input"

local overlay = mp.create_osd_overlay("ass-events")
overlay.z = 2000 -- ModernZ uses 1000; menus must stay above its fade/background.

local opened = false
local menu_name = nil
local items = {}
local cursor = 1
local first_visible = 1
local anchor_x = 0
local anchor_y = 0
local seekbar_y = 0
local playres_x = 0
local playres_y = 0
local geometry = nil
local placement = "progress"
local menu_stack = {}

local open_menu

local titles = {
    main = "Menu",
    open = "Abrir",
    tracks = "Faixas",
    playback = "Reprodução",
    speed = "Velocidade",
    editions = "Edições e títulos",
    video = "Vídeo",
    video_tracks = "Faixas de vídeo",
    aspect = "Proporção da imagem",
    audio_settings = "Áudio",
    subtitle_settings = "Legendas",
    window = "Janela",
    view = "Exibição",
    profiles = "Perfis",
    tools = "Ferramentas",
    audio = "Faixas de áudio",
    subtitles = "Legendas",
    playlist = "Lista de reprodução",
    chapters = "Capítulos",
    audio_device = "Dispositivo de áudio",
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function ass_color(rgb)
    rgb = tostring(rgb):gsub("#", "")
    return rgb:sub(5, 6) .. rgb:sub(3, 4) .. rgb:sub(1, 2)
end

local function ass_escape(value)
    value = tostring(value or "")
    local ok, escaped = pcall(mp.command_native, {"escape-ass", value})
    if ok and escaped then return escaped end
    return value:gsub("\\", "\\e"):gsub("{", "\\{"):gsub("}", "\\}")
end

local function display_name(entry, fallback)
    local title = entry.title
    if not title or title == "" then title = fallback end
    local details = {}
    if entry.lang and entry.lang ~= "" and entry.lang ~= "und" then
        details[#details + 1] = entry.lang:upper()
    end
    if entry.codec and entry.codec ~= "" then
        details[#details + 1] = entry.codec:upper()
    end
    if #details > 0 then title = title .. "  ·  " .. table.concat(details, " · ") end
    return title
end

local function get_tracks(kind)
    local result = {}
    for _, track in ipairs(mp.get_property_native("track-list", {}) or {}) do
        if track.type == kind then result[#result + 1] = track end
    end
    return result
end

local function build_audio()
    local result = {}
    for index, track in ipairs(get_tracks("audio")) do
        local id = track.id
        result[#result + 1] = {
            label = display_name(track, "Faixa " .. index),
            selected = track.selected == true,
            action = function() mp.set_property("aid", tostring(id)) end,
        }
    end
    if #result == 0 then result[1] = {label = "Nenhuma faixa de áudio", disabled = true} end
    return result
end

local function build_subtitles()
    local result = {}
    local subtitle_tracks = get_tracks("sub")
    local has_selected = false
    for _, track in ipairs(subtitle_tracks) do
        if track.selected then has_selected = true break end
    end
    result[1] = {
        label = "Desativadas",
        selected = not has_selected,
        action = function() mp.set_property("sid", "no") end,
    }
    for index, track in ipairs(subtitle_tracks) do
        local id = track.id
        result[#result + 1] = {
            label = display_name(track, "Legenda " .. index),
            selected = track.selected == true,
            action = function() mp.set_property("sid", tostring(id)) end,
        }
    end
    return result
end

local function build_playlist()
    local result = {}
    for index, entry in ipairs(mp.get_property_native("playlist", {}) or {}) do
        local label = entry.title
        if not label or label == "" then label = entry.filename or ("Item " .. index) end
        label = label:gsub("^.*[\\/]", "")
        local target = index - 1
        result[#result + 1] = {
            label = label,
            selected = entry.current == true or entry.playing == true,
            action = function() mp.commandv("playlist-play-index", tostring(target)) end,
        }
    end
    if #result == 0 then result[1] = {label = "Lista vazia", disabled = true} end
    return result
end

local function format_time(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, secs) end
    return string.format("%02d:%02d", minutes, secs)
end

local function build_chapters()
    local result = {}
    local current = mp.get_property_number("chapter", -1)
    for index, chapter in ipairs(mp.get_property_native("chapter-list", {}) or {}) do
        local target = index - 1
        local label = chapter.title
        if not label or label == "" then label = "Capítulo " .. index end
        label = format_time(chapter.time) .. "  " .. label
        result[#result + 1] = {
            label = label,
            selected = current == target,
            action = function() mp.set_property_number("chapter", target) end,
        }
    end
    if #result == 0 then result[1] = {label = "Nenhum capítulo", disabled = true} end
    return result
end

local function build_audio_devices()
    local result = {}
    local current = mp.get_property("audio-device", "auto")
    for _, device in ipairs(mp.get_property_native("audio-device-list", {}) or {}) do
        local name = device.name or "auto"
        local label = device.description or name
        result[#result + 1] = {
            label = label,
            selected = current == name,
            action = function() mp.set_property("audio-device", name) end,
        }
    end
    if #result == 0 then result[1] = {label = "Dispositivo automático", disabled = true} end
    return result
end

local function is_enabled(name)
    local value = mp.get_property_native(name, false)
    return value == true or value == "yes"
end

local function build_video_tracks()
    local result = {}
    for index, track in ipairs(get_tracks("video")) do
        local id = track.id
        result[#result + 1] = {
            label = display_name(track, "Faixa " .. index),
            selected = track.selected == true,
            action = function() mp.set_property("vid", tostring(id)) end,
        }
    end
    if #result == 0 then result[1] = {label = "Nenhuma faixa de vídeo", disabled = true} end
    return result
end

local function build_tracks()
    return {
        {label = "Vídeo", submenu = "video_tracks", hint = "g-v"},
        {label = "Áudio", submenu = "audio", hint = "g-a"},
        {label = "Legendas", submenu = "subtitles", hint = "g-s"},
    }
end

local function build_speed()
    local current = mp.get_property_number("speed", 1) or 1
    local result = {}
    for _, option in ipairs({
        {0.25, "0,25×"}, {0.50, "0,50×"}, {0.75, "0,75×"},
        {1.00, "Normal"}, {1.25, "1,25×"}, {1.50, "1,50×"},
        {1.75, "1,75×"}, {2.00, "2×"}, {4.00, "4×"},
    }) do
        local value = option[1]
        result[#result + 1] = {
            label = option[2],
            selected = math.abs(current - value) < 0.001,
            action = function() mp.set_property_number("speed", value) end,
        }
    end
    return result
end

local function build_playback()
    return {
        {label = "Velocidade", submenu = "speed", hint = string.format("%.2g×", mp.get_property_number("speed", 1) or 1)},
        {label = "Avançar 10 segundos", hint = "→", action = function() mp.commandv("seek", "10") end},
        {label = "Voltar 10 segundos", hint = "←", action = function() mp.commandv("seek", "-10") end},
        {label = "Próximo arquivo", hint = ">", action = function() mp.commandv("playlist-next", "weak") end},
        {label = "Arquivo anterior", hint = "<", action = function() mp.commandv("playlist-prev", "weak") end},
        {label = "Repetir arquivo", selected = mp.get_property("loop-file", "no") == "inf",
            action = function() mp.commandv("cycle-values", "loop-file", "inf", "no") end},
        {label = "Repetir lista", selected = mp.get_property("loop-playlist", "no") == "inf",
            action = function() mp.commandv("cycle-values", "loop-playlist", "inf", "no") end},
        {label = "Recarregar arquivo", action = function() mp.commandv("playlist-play-index", "current") end},
    }
end

local function build_editions()
    local result = {}
    local current = mp.get_property_number("edition", -1)
    for index, edition in ipairs(mp.get_property_native("edition-list", {}) or {}) do
        local id = edition.id
        if id == nil then id = index - 1 end
        local target = id
        result[#result + 1] = {
            label = edition.title and edition.title ~= "" and edition.title or ("Edição " .. index),
            selected = current == target,
            action = function() mp.set_property_number("edition", target) end,
        }
    end
    if #result == 0 then result[1] = {label = "Nenhuma edição disponível", disabled = true} end
    return result
end

local function build_aspect()
    local current = mp.get_property("video-aspect-override", "no")
    return {
        {label = "Automática", selected = current == "no" or current == "-1" or current == "-2",
            action = function() mp.set_property("video-aspect-override", "no") end},
        {label = "16:9", selected = current == "16:9",
            action = function() mp.set_property("video-aspect-override", "16:9") end},
        {label = "4:3", selected = current == "4:3",
            action = function() mp.set_property("video-aspect-override", "4:3") end},
        {label = "2,35:1", selected = current == "2.35:1" or current == "2.35",
            action = function() mp.set_property("video-aspect-override", "2.35:1") end},
    }
end

local function build_video()
    return {
        {label = "Faixa de vídeo", submenu = "video_tracks", hint = "g-v"},
        {label = "Proporção da imagem", submenu = "aspect"},
        {label = "Preencher a janela", selected = (mp.get_property_number("panscan", 0) or 0) > 0,
            action = function() mp.commandv("cycle-values", "panscan", "0", "1") end},
        {label = "Girar 90°", action = function() mp.commandv("cycle-values", "video-rotate", "90", "180", "270", "0") end},
        {label = "Remover bandas de cor", selected = is_enabled("deband"),
            action = function() mp.commandv("cycle", "deband") end},
        {label = "Desentrelaçar", selected = is_enabled("deinterlace"),
            action = function() mp.commandv("cycle", "deinterlace") end},
        {label = "Capturar imagem", hint = "s", action = function() mp.commandv("screenshot") end},
        {label = "Capturar sem legendas", action = function() mp.commandv("screenshot", "video") end},
    }
end

local function build_audio_settings()
    return {
        {label = "Faixa de áudio", submenu = "audio", hint = "g-a"},
        {label = "Dispositivo de saída", submenu = "audio_device"},
        {label = "Silenciar", selected = is_enabled("mute"), hint = "m",
            action = function() mp.commandv("cycle", "mute") end},
        {label = "Aumentar volume", hint = "+", action = function() mp.commandv("add", "volume", "2") end},
        {label = "Diminuir volume", hint = "−", action = function() mp.commandv("add", "volume", "-2") end},
        {label = "Adiantar áudio", action = function() mp.commandv("add", "audio-delay", "0.1") end},
        {label = "Atrasar áudio", action = function() mp.commandv("add", "audio-delay", "-0.1") end},
    }
end

local function build_subtitle_settings()
    return {
        {label = "Faixa de legenda", submenu = "subtitles", hint = "g-s"},
        {label = "Exibir legendas", selected = is_enabled("sub-visibility"),
            action = function() mp.commandv("cycle", "sub-visibility") end},
        {label = "Adiantar legenda", action = function() mp.commandv("add", "sub-delay", "0.1") end},
        {label = "Atrasar legenda", action = function() mp.commandv("add", "sub-delay", "-0.1") end},
        {label = "Aumentar legenda", action = function() mp.commandv("add", "sub-scale", "0.1") end},
        {label = "Diminuir legenda", action = function() mp.commandv("add", "sub-scale", "-0.1") end},
    }
end

local function build_window()
    return {
        {label = "Tela cheia", selected = is_enabled("fullscreen"), hint = "f",
            action = function() mp.commandv("cycle", "fullscreen") end},
        {label = "Sempre visível", selected = is_enabled("ontop"),
            action = function() mp.commandv("cycle", "ontop") end},
        {label = "Borda da janela", selected = is_enabled("border"),
            action = function() mp.commandv("cycle", "border") end},
        {label = "Tamanho 50%", action = function() mp.set_property_number("window-scale", 0.5) end},
        {label = "Tamanho 100%", action = function() mp.set_property_number("window-scale", 1) end},
        {label = "Tamanho 200%", action = function() mp.set_property_number("window-scale", 2) end},
        {label = "Capturar janela", action = function() mp.commandv("screenshot", "window") end},
    }
end

local function build_view()
    return {
        {label = "Painel de estatísticas", hint = "i",
            action = function() mp.commandv("script-binding", "modern_stats/toggle") end},
        {label = "Estatísticas técnicas do MPV",
            action = function() mp.commandv("script-binding", "stats/display-page-1-toggle") end},
        {label = "Mostrar tempo na tela",
            action = function() mp.commandv("cycle-values", "osd-level", "3", "1") end},
    }
end

local function build_profiles()
    local result = {}
    for _, profile in ipairs(mp.get_property_native("profile-list", {}) or {}) do
        local name = profile.name
        if name and name ~= "" and name:sub(1, 1) ~= "@" then
            local target = name
            result[#result + 1] = {
                label = name,
                action = function() mp.commandv("apply-profile", target) end,
            }
        end
    end
    if #result == 0 then result[1] = {label = "Nenhum perfil disponível", disabled = true} end
    return result
end

local function build_tools()
    return {
        {label = "Capturar imagem", hint = "s", action = function() mp.commandv("screenshot") end},
        {label = "Capturar sem legendas", action = function() mp.commandv("screenshot", "video") end},
        {label = "Ver atalhos configurados",
            action = function() mp.commandv("script-binding", "select/select-binding") end},
        {label = "Ver propriedades do MPV",
            action = function() mp.commandv("script-binding", "select/show-properties") end},
        {label = "Editar configurações",
            action = function() mp.commandv("script-binding", "select/edit-config-file") end},
    }
end

local function build_open()
    return {
        {label = "Abrir da área de transferência", action = function()
            local path = mp.get_property("clipboard/text", "")
            if path and path ~= "" then mp.commandv("loadfile", path) end
        end},
        {label = "Abrir do histórico",
            action = function() mp.commandv("script-binding", "select/select-watch-history") end},
        {label = "Continuar vídeo salvo",
            action = function() mp.commandv("script-binding", "select/select-watch-later") end},
    }
end

local function build_main()
    local paused = is_enabled("pause")
    return {
        {label = paused and "Reproduzir" or "Pausar", hint = "Espaço / p",
            action = function() mp.commandv("cycle", "pause") end},
        {label = "Abrir", submenu = "open"},
        {label = "Lista de reprodução", submenu = "playlist", hint = "g-p"},
        {label = "Faixas", submenu = "tracks", hint = "g-t"},
        {label = "Reprodução", submenu = "playback"},
        {label = "Capítulos", submenu = "chapters", hint = "g-c"},
        {label = "Edições e títulos", submenu = "editions", hint = "g-e"},
        {label = "Vídeo", submenu = "video"},
        {label = "Áudio", submenu = "audio_settings"},
        {label = "Legendas", submenu = "subtitle_settings"},
        {label = "Janela", submenu = "window"},
        {label = "Exibição", submenu = "view"},
        {label = "Perfis", submenu = "profiles"},
        {label = "Ferramentas", submenu = "tools"},
        {label = "Sair", hint = "q / Ctrl+W", action = function() mp.commandv("quit") end},
    }
end

local builders = {
    main = build_main,
    open = build_open,
    tracks = build_tracks,
    playback = build_playback,
    speed = build_speed,
    editions = build_editions,
    video = build_video,
    video_tracks = build_video_tracks,
    aspect = build_aspect,
    audio_settings = build_audio_settings,
    subtitle_settings = build_subtitle_settings,
    window = build_window,
    view = build_view,
    profiles = build_profiles,
    tools = build_tools,
    audio = build_audio,
    subtitles = build_subtitles,
    playlist = build_playlist,
    chapters = build_chapters,
    audio_device = build_audio_devices,
}

local function selected_index()
    for index, item in ipairs(items) do
        if item.selected then return index end
    end
    for index, item in ipairs(items) do
        if not item.disabled then return index end
    end
    return 1
end

local function notify_modernz(value)
    mp.commandv("script-message-to", "modernz", "modernz-menu-state", value)
end

local function clear_mouse_area()
    mp.set_mouse_area(0, 0, 0, 0, INPUT_GROUP)
end

local function close_menu()
    if not opened then return end
    opened = false
    menu_name = nil
    menu_stack = {}
    geometry = nil
    overlay:remove()
    clear_mouse_area()
    mp.disable_key_bindings(INPUT_GROUP)
    notify_modernz("closed")
end

local function real_dimensions()
    local dimensions = mp.get_property_native("osd-dimensions", {}) or {}
    return tonumber(dimensions.w) or 0, tonumber(dimensions.h) or 0
end

local function set_menu_mouse_area(x1, y1, x2, y2)
    local real_w, real_h = real_dimensions()
    if real_w <= 0 or real_h <= 0 or playres_x <= 0 or playres_y <= 0 then return end
    mp.set_mouse_area(
        x1 * real_w / playres_x,
        y1 * real_h / playres_y,
        x2 * real_w / playres_x,
        y2 * real_h / playres_y,
        INPUT_GROUP
    )
end

local function append_box(ass, x1, y1, x2, y2, radius, color, alpha)
    ass:new_event()
    ass:pos(0, 0)
    ass:an(7)
    ass:append(string.format("{\\bord0\\shad0\\1c&H%s&\\1a&H%02X&}", ass_color(color), alpha or 0))
    ass:draw_start()
    ass:round_rect_cw(x1, y1, x2, y2, radius)
    ass:draw_stop()
end

local function append_text(ass, x, y, text, font_size, color, bold, clip, align, outline_color, outline_size)
    ass:new_event()
    ass:pos(x, y)
    ass:an(align or 4)
    local border = outline_size or 0
    local outline = outline_color or "#000000"
    local style = string.format(
        "{\\fnSegoe UI\\fs%.1f\\bord%.2f\\shad0\\1c&H%s&\\3c&H%s&\\b%d\\q2}",
        font_size, border, ass_color(color), ass_color(outline), bold and 1 or 0
    )
    if clip then
        style = style .. string.format("{\\clip(%.1f,%.1f,%.1f,%.1f)}", clip[1], clip[2], clip[3], clip[4])
    end
    ass:append(style .. ass_escape(text))
end

local function ensure_cursor_visible(visible_count)
    if cursor < first_visible then first_visible = cursor end
    if cursor >= first_visible + visible_count then first_visible = cursor - visible_count + 1 end
    first_visible = clamp(first_visible, 1, math.max(1, #items - visible_count + 1))
end

local function render()
    if not opened or playres_x <= 0 or playres_y <= 0 then return end

    -- Keep the popup comfortably readable even in a small window. The old
    -- 0.62 minimum made both the surface and its labels look miniature.
    local scale = clamp(playres_y / 720, 0.86, 1.08)
    local outer_margin = 14 * scale
    local row_h = 48 * scale
    local header_h = 50 * scale
    local padding_x = 20 * scale
    local progress_gap = 11 * scale
    local font_size = 20 * scale
    local header_font_size = 20 * scale

    local longest = #(titles[menu_name] or "Menu")
    for _, item in ipairs(items) do
        local accessory_length = item.hint and (#item.hint + 3) or 0
        if item.submenu then accessory_length = accessory_length + 2 end
        longest = math.max(longest, #(item.label or "") + accessory_length)
    end
    local maximum_width = math.max(280 * scale, math.min(680 * scale, playres_x - outer_margin * 2))
    local minimum_width = math.min(450 * scale, maximum_width)
    local menu_w = clamp(longest * font_size * 0.54 + padding_x * 4, minimum_width, maximum_width)

    -- Button popups stay above the progress line. The context menu starts at
    -- the right-click position and shifts only enough to remain on-screen.
    local menu_bottom = seekbar_y - progress_gap
    local available_h = placement == "context"
        and math.max(row_h, playres_y - outer_margin * 2 - header_h)
        or math.max(row_h, menu_bottom - outer_margin - header_h)
    local visible_count = math.max(1, math.min(#items, math.floor(available_h / row_h)))
    ensure_cursor_visible(visible_count)

    local menu_h = header_h + visible_count * row_h
    local x1 = placement == "context"
        and clamp(anchor_x, outer_margin, playres_x - outer_margin - menu_w)
        or clamp(anchor_x - menu_w / 2, outer_margin, playres_x - outer_margin - menu_w)
    local x2 = x1 + menu_w
    local y1, y2
    if placement == "context" then
        y1 = clamp(anchor_y, outer_margin, playres_y - outer_margin - menu_h)
        y2 = y1 + menu_h
    else
        y2 = menu_bottom
        y1 = y2 - menu_h
    end

    geometry = {
        x1 = x1, y1 = y1, x2 = x2, y2 = y2,
        rows_y = y1 + header_h, row_h = row_h,
        visible_count = visible_count,
    }

    local ass = assdraw.ass_new()

    -- Single clean translucent surface: no fake border, no drop shadow and no
    -- pointer. This is much closer to YouTube's floating settings panel.
    append_box(ass, x1, y1, x2, y2, 12 * scale, "#080808", 0x3C)

    local title = titles[menu_name] or "Menu"
    if #items > visible_count then
        title = string.format("%s   %d–%d / %d", title, first_visible, first_visible + visible_count - 1, #items)
    end
    append_text(ass, x1 + padding_x, y1 + header_h / 2, title, header_font_size, "#FFFFFF", true,
        {x1 + padding_x, y1, x2 - padding_x, y1 + header_h})

    for visible_index = 1, visible_count do
        local item_index = first_visible + visible_index - 1
        local item = items[item_index]
        local row_y1 = y1 + header_h + (visible_index - 1) * row_h
        local row_y2 = row_y1 + row_h
        if item_index == cursor and not item.disabled then
            append_box(ass, x1 + 6 * scale, row_y1 + 3 * scale, x2 - 6 * scale, row_y2 - 3 * scale,
                7 * scale, "#3A3A3A", 0x42)
        end
        local text_x = x1 + padding_x
        local accessory_x = x2 - padding_x
        if item.submenu then accessory_x = accessory_x - 23 * scale end
        if item.hint then accessory_x = accessory_x - (#item.hint * font_size * 0.48 + 13 * scale) end
        local text_right = accessory_x
        local color = item.disabled and "#858585" or "#F4F4F4"
        append_text(ass, text_x, (row_y1 + row_y2) / 2, item.label, font_size, color,
            item.selected == true, {text_x, row_y1, text_right, row_y2}, nil,
            item.selected and "#D71919" or nil, item.selected and (0.52 * scale) or nil)
        if item.submenu then
            append_text(ass, x2 - padding_x, (row_y1 + row_y2) / 2, "›", font_size + 2 * scale,
                "#BEBEBE", false, {x2 - padding_x - 16 * scale, row_y1, x2 - 5 * scale, row_y2}, 6)
        end
        if item.hint then
            local hint_right = x2 - padding_x - (item.submenu and 25 * scale or 0)
            append_text(ass, hint_right, (row_y1 + row_y2) / 2, item.hint, font_size * 0.82,
                item.disabled and "#686868" or "#A9A9A9", false,
                {text_right, row_y1, hint_right, row_y2}, 6)
        end
    end

    overlay.res_x = playres_x
    overlay.res_y = playres_y
    overlay.data = ass.text
    overlay.z = 2000
    overlay:update()

    -- Capture only the popup itself. The rest of the ModernZ bar remains
    -- clickable, so clicking another launcher can replace this menu directly.
    set_menu_mouse_area(x1, y1, x2, y2)
end

local function rebuild(menu)
    menu_name = builders[menu] and menu or "main"
    items = builders[menu_name]()
    if #menu_stack > 0 then
        table.insert(items, 1, {label = "‹ Voltar", back = true})
    end
    cursor = selected_index()
    first_visible = 1
end

local function activate()
    local item = items[cursor]
    if not item or item.disabled then return end
    if item.back then
        local previous = table.remove(menu_stack)
        rebuild(previous or "main")
        render()
        return
    end
    if item.submenu then
        menu_stack[#menu_stack + 1] = menu_name
        rebuild(item.submenu)
        render()
        return
    end
    local action = item.action
    close_menu()
    if action then
        local ok, err = pcall(action)
        if not ok then mp.msg.error("Falha ao executar item do menu: " .. tostring(err)) end
    end
end

local function move_cursor(delta)
    if #items == 0 then return end
    local candidate = cursor
    repeat
        candidate = ((candidate - 1 + delta) % #items) + 1
    until not items[candidate].disabled or candidate == cursor
    cursor = candidate
    render()
end

local function mouse_to_virtual()
    local real_w, real_h = real_dimensions()
    if real_w <= 0 or real_h <= 0 then return -1, -1 end
    local mouse_x, mouse_y = mp.get_mouse_pos()
    return mouse_x * playres_x / real_w, mouse_y * playres_y / real_h
end

local function mouse_move()
    if not opened or not geometry then return end
    local mouse_x, mouse_y = mouse_to_virtual()
    if mouse_x < geometry.x1 or mouse_x > geometry.x2 or
        mouse_y < geometry.rows_y or mouse_y > geometry.y2 then return end
    local visible_index = math.floor((mouse_y - geometry.rows_y) / geometry.row_h) + 1
    visible_index = clamp(visible_index, 1, geometry.visible_count)
    local item_index = first_visible + visible_index - 1
    if items[item_index] and cursor ~= item_index then
        cursor = item_index
        render()
    end
end

local function mouse_click()
    if not opened or not geometry then return end
    local mouse_x, mouse_y = mouse_to_virtual()
    if mouse_x < geometry.x1 or mouse_x > geometry.x2 or
        mouse_y < geometry.rows_y or mouse_y > geometry.y2 then return end
    mouse_move()
    activate()
end

mp.set_key_bindings({
    {"mouse_move", mouse_move},
    {"mbtn_left", mouse_click},
    {"mbtn_right", close_menu},
    {"wheel_up", function() move_cursor(-1) end},
    {"wheel_down", function() move_cursor(1) end},
    {"UP", function() move_cursor(-1) end},
    {"DOWN", function() move_cursor(1) end},
    {"HOME", function() cursor = 1; render() end},
    {"END", function() cursor = #items; render() end},
    {"ENTER", activate},
    {"KP_ENTER", activate},
    {"ESC", close_menu},
    {"LEFT", function()
        if #menu_stack > 0 then
            local previous = table.remove(menu_stack)
            rebuild(previous or "main")
            render()
        end
    end},
    {"RIGHT", function()
        local item = items[cursor]
        if item and item.submenu then activate() end
    end},
}, INPUT_GROUP, "force")
mp.disable_key_bindings(INPUT_GROUP)

open_menu = function(name, x, progress_y, res_x, res_y, requested_placement)
    x = tonumber(x)
    progress_y = tonumber(progress_y)
    res_x = tonumber(res_x)
    res_y = tonumber(res_y)
    if not x or not progress_y or not res_x or not res_y or res_x <= 0 or res_y <= 0 then return end

    -- The launcher is the toggle. A second click on the same button closes
    -- its menu regardless of the exact pixel clicked inside that button.
    if opened and menu_name == name then
        close_menu()
        return
    end

    anchor_x = x
    anchor_y = progress_y
    seekbar_y = progress_y
    playres_x = res_x
    playres_y = res_y
    placement = requested_placement == "context" and "context" or "progress"
    menu_stack = {}
    rebuild(name)
    opened = true
    mp.enable_key_bindings(INPUT_GROUP, "allow-hide-cursor")
    notify_modernz("open")
    render()
end

mp.register_script_message("open-at", open_menu)

-- Direct bindings are retained as a safe fallback. The patched ModernZ path
-- uses open-at because it can supply the seekbar's exact responsive geometry.
local function fallback_open(name)
    local width, height = real_dimensions()
    if width <= 0 or height <= 0 then return end
    local mouse_x = mp.get_mouse_pos()
    open_menu(name, mouse_x, height - math.max(48, height * 0.075), width, height)
end

for _, name in ipairs({"main", "audio", "subtitles", "playlist", "chapters", "audio_device"}) do
    local binding_name = name
    mp.add_key_binding(nil, binding_name, function() fallback_open(binding_name) end)
end

-- Replaces mpv's compact native right-click menu with the same readable,
-- translucent Portuguese surface used by ModernZ's button menus.
mp.add_key_binding(nil, "context", function()
    local width, height = real_dimensions()
    if width <= 0 or height <= 0 then return end
    local mouse_x, mouse_y = mp.get_mouse_pos()
    open_menu("main", mouse_x, mouse_y, width, height, "context")
end)

mp.register_event("start-file", close_menu)
mp.register_event("shutdown", close_menu)

mp.observe_property("fullscreen", "bool", function()
    if opened then close_menu() end
end)
