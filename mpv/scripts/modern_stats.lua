local mp = require "mp"
local assdraw = require "mp.assdraw"
local options = require "mp.options"

local overlay = mp.create_osd_overlay("ass-events")
overlay.z = 900 -- ModernZ remains visible above the dashboard when hovered.

local visible = false
local timer = nil

local user_opts = {
    -- auto follows the operating-system UI language. It can also be forced
    -- to pt, en or es in script-opts/modern_stats.conf.
    language = "auto",
}
options.read_options(user_opts, "modern_stats")

local COLORS = {
    panel = "#080808",
    card = "#141414",
    accent = "#CC0000",
    text = "#F5F5F5",
    muted = "#A8A8A8",
    dim = "#707070",
    good = "#43C67A",
    warning = "#F2B84B",
    bad = "#F05D5E",
    neutral = "#78A9FF",
}

local LANGUAGES = {
    en = {
        panel_title = "PLAYBACK DASHBOARD",
        file_title = "FILE", file_subtitle = "Source and storage",
        playback_title = "PLAYBACK", playback_subtitle = "Sync and stability",
        video_title = "VIDEO", video_subtitle = "Picture and decoding",
        audio_title = "AUDIO", audio_subtitle = "Sound and output device",
        size = "Size", container = "Container", cache = "Cache", duration = "Duration",
        state = "State", av_sync = "A/V sync", dropped_frames = "Dropped frames",
        display = "Display", rendering = "Rendering", codec = "Codec",
        resolution = "Resolution", frame_rate = "Frame rate", acceleration = "Acceleration",
        pixel_format = "Pixel format", bitrate = "Bitrate", color = "Color",
        channels = "Channels", sample_rate = "Sample rate", output = "Output", volume = "Volume",
        no_cache = "No cache", seconds_ahead = "%.1f s ahead", minutes_ahead = "%d min %02d s ahead",
        perfect = "Perfect", decoding_output = "decoding %d / output %d",
        synchronized = "Synchronized", slight_difference = "Slight difference", out_of_sync = "Out of sync",
        disabled_f = "Disabled", active_f = "Active", loading = "Loading", paused = "Paused", playing = "Playing",
        no_file = "No file loaded", muted = "Muted", stereo = "Stereo", mono = "Mono", surround = "Surround",
        close_hint = "ⓘ again or Esc to close", auto_update = "Automatic update",
    },
    pt = {
        panel_title = "PAINEL DE REPRODUÇÃO",
        file_title = "ARQUIVO", file_subtitle = "Origem e armazenamento",
        playback_title = "REPRODUÇÃO", playback_subtitle = "Sincronia e estabilidade",
        video_title = "VÍDEO", video_subtitle = "Imagem e decodificação",
        audio_title = "ÁUDIO", audio_subtitle = "Som e dispositivo de saída",
        size = "Tamanho", container = "Contêiner", cache = "Cache", duration = "Duração",
        state = "Estado", av_sync = "Sincronização A/V", dropped_frames = "Quadros perdidos",
        display = "Tela", rendering = "Renderização", codec = "Codec",
        resolution = "Resolução", frame_rate = "Taxa de quadros", acceleration = "Aceleração",
        pixel_format = "Formato de pixel", bitrate = "Bitrate", color = "Cor",
        channels = "Canais", sample_rate = "Amostragem", output = "Saída", volume = "Volume",
        no_cache = "Sem cache", seconds_ahead = "%.1f s à frente", minutes_ahead = "%d min %02d s à frente",
        perfect = "Perfeito", decoding_output = "decodificação %d / saída %d",
        synchronized = "Sincronizado", slight_difference = "Pequena diferença", out_of_sync = "Fora de sincronia",
        disabled_f = "Desativada", active_f = "Ativa", loading = "Carregando", paused = "Pausado", playing = "Reproduzindo",
        no_file = "Nenhum arquivo carregado", muted = "Mudo", stereo = "Estéreo", mono = "Mono", surround = "Surround",
        close_hint = "ⓘ novamente ou Esc para fechar", auto_update = "Atualização automática",
    },
    es = {
        panel_title = "PANEL DE REPRODUCCIÓN",
        file_title = "ARCHIVO", file_subtitle = "Origen y almacenamiento",
        playback_title = "REPRODUCCIÓN", playback_subtitle = "Sincronía y estabilidad",
        video_title = "VÍDEO", video_subtitle = "Imagen y decodificación",
        audio_title = "AUDIO", audio_subtitle = "Sonido y dispositivo de salida",
        size = "Tamaño", container = "Contenedor", cache = "Caché", duration = "Duración",
        state = "Estado", av_sync = "Sincronización A/V", dropped_frames = "Fotogramas perdidos",
        display = "Pantalla", rendering = "Renderizado", codec = "Códec",
        resolution = "Resolución", frame_rate = "Tasa de fotogramas", acceleration = "Aceleración",
        pixel_format = "Formato de píxel", bitrate = "Tasa de bits", color = "Color",
        channels = "Canales", sample_rate = "Muestreo", output = "Salida", volume = "Volumen",
        no_cache = "Sin caché", seconds_ahead = "%.1f s por delante", minutes_ahead = "%d min %02d s por delante",
        perfect = "Perfecto", decoding_output = "decodificación %d / salida %d",
        synchronized = "Sincronizado", slight_difference = "Pequeña diferencia", out_of_sync = "Fuera de sincronía",
        disabled_f = "Desactivada", active_f = "Activa", loading = "Cargando", paused = "Pausado", playing = "Reproduciendo",
        no_file = "Ningún archivo cargado", muted = "Silenciado", stereo = "Estéreo", mono = "Mono", surround = "Envolvente",
        close_hint = "ⓘ de nuevo o Esc para cerrar", auto_update = "Actualización automática",
    },
}

local function normalize_language(value)
    value = tostring(value or ""):lower():gsub("_", "-")
    local prefix = value:match("^%s*([a-z][a-z])")
    if LANGUAGES[prefix] then return prefix end
    return nil
end

local function subprocess_output(args)
    local ok, result = pcall(mp.command_native, {
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = false,
        args = args,
    })
    if not ok or type(result) ~= "table" or result.status ~= 0 then return nil end
    return tostring(result.stdout or ""):match("^%s*(.-)%s*$")
end

local function detect_system_language()
    for _, variable in ipairs({"LC_ALL", "LC_MESSAGES", "LANGUAGE", "LANG"}) do
        local detected = normalize_language(os.getenv(variable))
        if detected then return detected end
    end

    local platform = tostring(mp.get_property("platform", "") or ""):lower()
    local locale
    if platform == "windows" then
        locale = subprocess_output({
            "powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
            "[System.Globalization.CultureInfo]::CurrentUICulture.Name",
        })
    elseif platform == "darwin" or platform == "macos" then
        locale = subprocess_output({"defaults", "read", "-g", "AppleLocale"})
    end
    return normalize_language(locale) or "en"
end

local selected_language = normalize_language(user_opts.language)
if tostring(user_opts.language):lower() == "auto" or not selected_language then
    selected_language = detect_system_language()
end
local locale = LANGUAGES[selected_language] or LANGUAGES.en

local function tr(key, ...)
    local value = locale[key] or LANGUAGES.en[key] or key
    if select("#", ...) > 0 then return string.format(value, ...) end
    return value
end

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

local function property(name, fallback)
    local value = mp.get_property(name)
    if value == nil or value == "" or value == "no" then return fallback or "—" end
    return value
end

local function native(name, fallback)
    local value = mp.get_property_native(name)
    if value == nil then return fallback end
    return value
end

local function number(name, fallback)
    return mp.get_property_number(name, fallback or 0) or (fallback or 0)
end

local function basename(path)
    path = tostring(path or "")
    return path:gsub("^.*[\\/]", "")
end

local function format_bytes(bytes)
    bytes = tonumber(bytes)
    if not bytes or bytes <= 0 then return "—" end
    local units = {"B", "KiB", "MiB", "GiB", "TiB"}
    local index = 1
    while bytes >= 1024 and index < #units do
        bytes = bytes / 1024
        index = index + 1
    end
    local decimals = index <= 2 and 0 or (bytes >= 100 and 0 or bytes >= 10 and 1 or 2)
    return string.format("%." .. decimals .. "f %s", bytes, units[index])
end

local function format_bitrate(bits)
    bits = tonumber(bits)
    if not bits or bits <= 0 then return "—" end
    if bits >= 1000000 then return string.format("%.2f Mbps", bits / 1000000) end
    return string.format("%.0f kbps", bits / 1000)
end

local function format_fps(value)
    value = tonumber(value)
    if not value or value <= 0 then return "—" end
    local formatted = string.format("%.3f fps", value)
    formatted = formatted:gsub("0+ fps$", " fps")
    formatted = formatted:gsub("%. fps$", " fps")
    return formatted
end

local function format_hz(value)
    value = tonumber(value)
    if not value or value <= 0 then return "—" end
    local formatted = string.format("%.2f Hz", value)
    formatted = formatted:gsub("%.00 Hz$", " Hz")
    return formatted
end

local function format_duration(seconds)
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 then return tr("no_cache") end
    if seconds < 60 then return tr("seconds_ahead", seconds) end
    return tr("minutes_ahead", math.floor(seconds / 60), math.floor(seconds % 60))
end

local function aspect_label(width, height)
    width, height = tonumber(width), tonumber(height)
    if not width or not height or height == 0 then return nil end
    local ratio = width / height
    local known = {
        {2.40, "2.40:1"}, {2.35, "2.35:1 (Scope)"}, {2.00, "2:1"},
        {16 / 9, "16:9"}, {16 / 10, "16:10"}, {4 / 3, "4:3"},
    }
    for _, candidate in ipairs(known) do
        if math.abs(ratio - candidate[1]) < 0.025 then return candidate[2] end
    end
    return string.format("%.2f:1", ratio)
end

local function friendly_video_codec(codec)
    codec = tostring(codec or ""):lower()
    local names = {
        h264 = "H.264 / AVC", avc = "H.264 / AVC",
        hevc = "H.265 / HEVC", h265 = "H.265 / HEVC",
        av1 = "AV1", vp9 = "VP9", vp8 = "VP8",
        mpeg2video = "MPEG-2", prores = "Apple ProRes",
    }
    return names[codec] or (codec ~= "" and codec:upper() or "—")
end

local function friendly_audio_codec(codec)
    codec = tostring(codec or ""):lower()
    local names = {
        aac = "AAC", mp3 = "MP3", opus = "Opus", vorbis = "Vorbis",
        flac = "FLAC", alac = "ALAC", ac3 = "Dolby Digital (AC-3)",
        eac3 = "Dolby Digital Plus (E-AC-3)", dts = "DTS",
    }
    return names[codec] or (codec ~= "" and codec:upper() or "—")
end

local function channel_label(channels)
    channels = tostring(channels or "")
    local names = {
        stereo = "2.0 · " .. tr("stereo"), mono = "1.0 · " .. tr("mono"),
        ["2"] = "2.0 · " .. tr("stereo"), ["1"] = "1.0 · " .. tr("mono"),
        ["5.1"] = "5.1 · " .. tr("surround"), ["7.1"] = "7.1 · " .. tr("surround"),
    }
    return names[channels] or (channels ~= "" and channels or "—")
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

local function append_text(ass, x, y, text, size, color, bold, align, clip)
    ass:new_event()
    ass:pos(x, y)
    ass:an(align or 4)
    local style = string.format(
        "{\\fnSegoe UI\\fs%.1f\\bord0\\shad0\\1c&H%s&\\b%d\\q2}",
        size, ass_color(color), bold and 1 or 0
    )
    if clip then
        style = style .. string.format("{\\clip(%.1f,%.1f,%.1f,%.1f)}", clip[1], clip[2], clip[3], clip[4])
    end
    ass:append(style .. ass_escape(text))
end

local function append_line(ass, x1, y, x2, thickness, color, alpha)
    append_box(ass, x1, y, x2, y + thickness, 0, color, alpha)
end

local function collect_data()
    local video = native("video-params", {}) or {}
    local video_out = native("video-out-params", {}) or {}
    local audio = native("audio-params", {}) or {}
    local cache = native("demuxer-cache-state", {}) or {}

    local width = video.w or video.dw or video_out.w or video_out.dw
    local height = video.h or video.dh or video_out.h or video_out.dh
    local display_width = video_out.dw or width
    local display_height = video_out.dh or height
    local aspect = aspect_label(display_width, display_height)
    local resolution = width and height and string.format("%d × %d", width, height) or "—"
    if aspect then resolution = resolution .. "  ·  " .. aspect end

    local decoder_drops = number("decoder-frame-drop-count", 0)
    local output_drops = number("frame-drop-count", 0)
    local total_drops = decoder_drops + output_drops
    local drop_color = total_drops == 0 and COLORS.good or (total_drops < 10 and COLORS.warning or COLORS.bad)
    local drop_value = total_drops == 0 and ("0 · " .. tr("perfect"))
        or string.format("%d · %s", total_drops, tr("decoding_output", decoder_drops, output_drops))

    local avsync = number("avsync", 0)
    local av_abs = math.abs(avsync)
    local av_color = av_abs < 0.04 and COLORS.good or (av_abs < 0.10 and COLORS.warning or COLORS.bad)
    local av_state = av_abs < 0.04 and tr("synchronized")
        or (av_abs < 0.10 and tr("slight_difference") or tr("out_of_sync"))
    local av_value = string.format("%+.4f s · %s", avsync, av_state)

    local hwdec = property("hwdec-current", tr("disabled_f"))
    local hw_color = hwdec == tr("disabled_f") and COLORS.warning or COLORS.good
    if hwdec ~= tr("disabled_f") then hwdec = hwdec:upper() .. " · " .. tr("active_f") end

    local pause = native("pause", false)
    local paused_cache = native("paused-for-cache", false)
    local playback_state = paused_cache and tr("loading") or (pause and tr("paused") or tr("playing"))
    local playback_color = paused_cache and COLORS.warning or (pause and COLORS.neutral or COLORS.good)

    local filename = basename(property("filename", tr("no_file")))
    local container = property("file-format", property("demuxer", "—")):upper()
    local cache_duration = cache["cache-duration"] or number("demuxer-cache-duration", 0)

    local display_fps = number("display-fps", number("estimated-display-fps", 0))
    local source_fps = number("container-fps", number("estimated-vf-fps", 0))
    local gpu_context = property("current-gpu-context", "—")
    local renderer = property("current-vo", "—")
    if gpu_context ~= "—" then renderer = renderer .. " · " .. gpu_context end

    local color_info = {}
    local primaries = video.primaries or property("video-params/primaries", nil)
    local transfer = video.gamma or video.transfer or property("video-params/gamma", nil)
    local matrix = video.colormatrix or property("video-params/colormatrix", nil)
    if primaries and primaries ~= "—" then color_info[#color_info + 1] = tostring(primaries) end
    if transfer and transfer ~= "—" then color_info[#color_info + 1] = tostring(transfer) end
    if matrix and matrix ~= "—" then color_info[#color_info + 1] = tostring(matrix) end

    local sample_rate = tonumber(audio.samplerate) or number("audio-params/samplerate", 0)
    local channels = audio["hr-channels"] or audio["channel-count"] or audio.channels or property("audio-params/hr-channels", "—")
    local volume = number("volume", 0)
    local muted = native("mute", false)
    local volume_value = muted and string.format("%.0f%% · %s", volume, tr("muted")) or string.format("%.0f%%", volume)
    local volume_color = muted and COLORS.bad or (volume > 100 and COLORS.warning or COLORS.text)

    return {
        filename = filename,
        header_status = playback_state,
        header_color = playback_color,
        file = {
            {tr("size"), format_bytes(number("file-size", 0))},
            {tr("container"), container},
            {tr("cache"), format_duration(cache_duration)},
            {tr("duration"), property("duration", "—") ~= "—" and mp.format_time(number("duration", 0)) or "—"},
        },
        playback = {
            {tr("state"), playback_state, playback_color},
            {tr("av_sync"), av_value, av_color},
            {tr("dropped_frames"), drop_value, drop_color},
            {tr("display"), format_hz(display_fps)},
            {tr("rendering"), renderer},
        },
        video = {
            {tr("codec"), friendly_video_codec(property("video-codec", ""))},
            {tr("resolution"), resolution},
            {tr("frame_rate"), format_fps(source_fps)},
            {tr("acceleration"), hwdec, hw_color},
            {tr("pixel_format"), property("video-params/pixelformat", video.pixelformat or "—")},
            {tr("bitrate"), format_bitrate(number("video-bitrate", 0))},
            {tr("color"), #color_info > 0 and table.concat(color_info, " · ") or "—"},
        },
        audio = {
            {tr("codec"), friendly_audio_codec(property("audio-codec", ""))},
            {tr("channels"), channel_label(channels)},
            {tr("sample_rate"), sample_rate > 0 and string.format("%.1f kHz", sample_rate / 1000) or "—"},
            {tr("bitrate"), format_bitrate(number("audio-bitrate", 0))},
            {tr("output"), property("current-ao", "—")},
            {tr("volume"), volume_value, volume_color},
        },
    }
end

local function draw_status_pill(ass, x2, y, label, color, font_size)
    local width = math.max(92, #label * font_size * 0.53 + 32)
    local height = font_size + 13
    append_box(ass, x2 - width, y - height / 2, x2, y + height / 2, height / 2, color, 0xB8)
    append_box(ass, x2 - width + 10, y - 3, x2 - width + 16, y + 3, 3, color, 0)
    append_text(ass, x2 - width + 23, y, label, font_size, COLORS.text, true, 4)
    return width
end

local function draw_card(ass, x1, y1, x2, y2, title, subtitle, rows)
    -- One softly translucent surface, without the old double outline.  The
    -- dashboard keeps its hierarchy while sharing the clean floating finish
    -- of ModernZ's menus.
    append_box(ass, x1, y1, x2, y2, 10, COLORS.card, 0x6C)
    append_box(ass, x1 + 14, y1 + 17, x1 + 19, y1 + 39, 2.5, COLORS.accent, 0)
    append_text(ass, x1 + 29, y1 + 23, title, 20, COLORS.text, true, 7)
    append_text(ass, x1 + 29, y1 + 47, subtitle, 11, COLORS.dim, false, 7)

    local content_top = y1 + 67
    local content_bottom = y2 - 10
    local row_h = (content_bottom - content_top) / math.max(1, #rows)
    local label_x = x1 + 20
    local value_x = x2 - 20
    local divider = x1 + (x2 - x1) * 0.38

    for index, row in ipairs(rows) do
        local row_y1 = content_top + (index - 1) * row_h
        local row_y2 = row_y1 + row_h
        local center_y = (row_y1 + row_y2) / 2
        if index > 1 then append_line(ass, x1 + 18, row_y1, x2 - 18, 1, "#292929", 0x20) end
        append_text(ass, label_x, center_y, row[1], 13, COLORS.muted, false, 4,
            {label_x, row_y1, divider - 8, row_y2})
        append_text(ass, value_x, center_y, row[2], 14, row[3] or COLORS.text, row[3] ~= nil, 6,
            {divider, row_y1, value_x, row_y2})
    end
end

local function render()
    if not visible then return end
    local dimensions = native("osd-dimensions", {}) or {}
    local width = tonumber(dimensions.w) or 0
    local height = tonumber(dimensions.h) or 0
    local aspect = tonumber(dimensions.aspect) or (height > 0 and width / height or 0)
    if width <= 0 or height <= 0 or aspect <= 0 then return end

    local res_y = 720
    local res_x = res_y * aspect
    local data = collect_data()
    local ass = assdraw.ass_new()

    local margin_x = clamp(res_x * 0.035, 28, 46)
    local top = 28
    local bottom = res_y - 52 -- leaves room for ModernZ when the mouse reaches the bottom
    -- Same surface treatment used by the approved popup menus: translucent
    -- near-black, clean rounded corners, no border and no shadow.
    append_box(ass, margin_x, top, res_x - margin_x, bottom, 12, COLORS.panel, 0x3C)

    local inner_x1 = margin_x + 24
    local inner_x2 = res_x - margin_x - 24
    local header_y = top + 26

    append_box(ass, inner_x1, header_y, inner_x1 + 38, header_y + 38, 19, COLORS.accent, 0)
    append_text(ass, inner_x1 + 19, header_y + 19, "i", 24, COLORS.text, true, 5)
    append_text(ass, inner_x1 + 52, header_y + 3, tr("panel_title"), 22, COLORS.text, true, 7)
    append_text(ass, inner_x1 + 52, header_y + 34, data.filename, 14, COLORS.muted, false, 7,
        {inner_x1 + 52, header_y + 23, inner_x2 - 190, header_y + 48})
    draw_status_pill(ass, inner_x2, header_y + 19, data.header_status, data.header_color, 13)
    append_line(ass, inner_x1, top + 82, inner_x2, 3, COLORS.accent, 0)

    local cards_top = top + 101
    local cards_bottom = bottom - 49
    local gap_x = 16
    local gap_y = 16
    local column_w = (inner_x2 - inner_x1 - gap_x) / 2
    local row_h = (cards_bottom - cards_top - gap_y) / 2
    local left_x1 = inner_x1
    local left_x2 = inner_x1 + column_w
    local right_x1 = left_x2 + gap_x
    local right_x2 = inner_x2
    local first_y1 = cards_top
    local first_y2 = cards_top + row_h
    local second_y1 = first_y2 + gap_y
    local second_y2 = cards_bottom

    draw_card(ass, left_x1, first_y1, left_x2, first_y2,
        tr("file_title"), tr("file_subtitle"), data.file)
    draw_card(ass, right_x1, first_y1, right_x2, first_y2,
        tr("playback_title"), tr("playback_subtitle"), data.playback)
    draw_card(ass, left_x1, second_y1, left_x2, second_y2,
        tr("video_title"), tr("video_subtitle"), data.video)
    draw_card(ass, right_x1, second_y1, right_x2, second_y2,
        tr("audio_title"), tr("audio_subtitle"), data.audio)

    append_text(ass, inner_x1, bottom - 24,
        tr("close_hint"), 12, COLORS.dim, false, 7)
    append_text(ass, inner_x2, bottom - 24,
        tr("auto_update"), 12, COLORS.dim, false, 9)

    overlay.res_x = res_x
    overlay.res_y = res_y
    overlay.data = ass.text
    overlay.z = 900
    overlay:update()
end

local function close()
    if not visible then return end
    visible = false
    overlay:remove()
    mp.disable_key_bindings("modern_stats_close")
    if timer then timer:kill() end
end

local function open()
    if visible then return end
    visible = true
    mp.enable_key_bindings("modern_stats_close")
    render()
    if not timer then timer = mp.add_periodic_timer(0.5, render) end
    timer:resume()
end

local function toggle()
    if visible then close() else open() end
end

mp.set_key_bindings({
    {"ESC", close},
}, "modern_stats_close", "force")
mp.disable_key_bindings("modern_stats_close")

mp.add_key_binding(nil, "toggle", toggle)
mp.register_script_message("toggle", toggle)
mp.register_event("start-file", function() if visible then render() end end)
mp.register_event("shutdown", close)
mp.observe_property("osd-dimensions", "native", function() if visible then render() end end)
