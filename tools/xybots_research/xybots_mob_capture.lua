-- Xybots live motion-object recorder for MAME.
-- Private research only. This records sprite table metadata, not ROM graphics.

local output_dir = "D:/Godot/xybotsResearch/exports/live_mob_capture"
local sample_every_frames = 2
local max_frames = 21600

local function mkdir(path)
    os.execute('if not exist "' .. path .. '" mkdir "' .. path .. '"')
end

local function hex4(value)
    return string.format("%04X", value & 0xffff)
end

local function signed9(value)
    value = value & 0x1ff
    if value >= 0x100 then
        return value - 0x200
    end
    return value
end

mkdir(output_dir)

local started_at = os.date("%Y-%m-%d_%H%M%S")
local csv_path = output_dir .. "/mob_capture_" .. started_at .. ".csv"
local writes_path = output_dir .. "/mob_writes_" .. started_at .. ".csv"
local log_path = output_dir .. "/mob_capture_" .. started_at .. ".txt"

local csv = assert(io.open(csv_path, "w"))
local writes = assert(io.open(writes_path, "w"))
local log = assert(io.open(log_path, "w"))

csv:write("frame,entry,active,word0,word1,word2,word3,code_hex,code_dec,x_raw,x_signed,y_raw,y_signed,height_field,height_tiles,color,priority,hflip\n")
writes:write("frame,address,entry,word_index,data,mem_mask,code_hex,height_tiles,color,priority,hflip\n")

log:write("Xybots live motion-object capture\n")
log:write("Started: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
log:write("MAME system: " .. emu.romname() .. "\n")
log:write("Output CSV: " .. csv_path .. "\n\n")
log:write("Write-tap CSV: " .. writes_path .. "\n")
log:write("Interpretation is based on MAME 0.288 src/mame/atari/xybots.cpp s_mob_config.\n")
log:write("Motion-object RAM share: :mob, mapped by driver at 0x802e00-0x802fff.\n")
log:write("Each entry is four 16-bit words. Empty/inactive detection is heuristic.\n")
log:flush()

local frame = 0
local mob = nil
local shadow = {}

for i = 0, 63 do
    shadow[i] = { 0, 0, 0, 0 }
end

local function find_mob_share()
    if mob ~= nil then
        return mob
    end

    mob = manager.machine.memory.shares[":mob"]
    if mob == nil then
        mob = manager.machine.memory.shares["mob"]
    end
    return mob
end

local function capture_frame()
    frame = frame + 1

    if frame > max_frames then
        return
    end

    if (frame % sample_every_frames) ~= 0 then
        return
    end

    local share = find_mob_share()
    if share == nil then
        log:write("Frame " .. frame .. ": mob share not found\n")
        log:flush()
        return
    end

    for entry = 0, 63 do
        local offs = entry * 4
        local w0 = share:read_u16(offs + 0)
        local w1 = share:read_u16(offs + 1)
        local w2 = share:read_u16(offs + 2)
        local w3 = share:read_u16(offs + 3)

        local code = w0 & 0x3fff
        local hflip = ((w0 & 0x8000) ~= 0) and 1 or 0
        local priority = w1 & 0x000f
        local height_field = w2 & 0x0007
        local height_tiles = height_field + 1
        local y_raw = (w2 & 0xff80) >> 7
        local x_raw = (w3 & 0xff80) >> 7
        local y_signed = signed9(y_raw)
        local x_signed = signed9(x_raw)
        local color = w3 & 0x000f

        -- Heuristic only: active entries usually have some nonzero position, code, color,
        -- height, or priority. Keep all rows so the raw table remains auditable.
        local active = ((w0 | w1 | w2 | w3) ~= 0) and 1 or 0

        csv:write(string.format(
            "%d,%d,%d,%s,%s,%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
            frame, entry, active,
            hex4(w0), hex4(w1), hex4(w2), hex4(w3),
            hex4(code), code, x_raw, x_signed, y_raw, y_signed,
            height_field, height_tiles, color, priority, hflip
        ))
    end
        csv:flush()
end

-- Keep notifier subscriptions in a global table. If they only live in locals,
-- Lua may collect them after the autoboot script finishes, stopping capture.
_G.xybots_mob_capture = _G.xybots_mob_capture or {}
_G.xybots_mob_capture.frame_sub = emu.add_machine_frame_notifier(capture_frame)

local function decode_shadow(entry)
    local row = shadow[entry]
    local w0 = row[1]
    local w1 = row[2]
    local w2 = row[3]
    local w3 = row[4]
    local code = w0 & 0x3fff
    local hflip = ((w0 & 0x8000) ~= 0) and 1 or 0
    local priority = w1 & 0x000f
    local height_tiles = (w2 & 0x0007) + 1
    local color = w3 & 0x000f
    return code, height_tiles, color, priority, hflip
end

local function on_mob_write(offset, data, mem_mask)
    local rel = offset - 0x802e00
    if rel < 0 or rel > 0x1ff then
        return data
    end

    local word_offset = math.floor(rel / 2)
    local entry = math.floor(word_offset / 4)
    local word_index = word_offset % 4

    if entry >= 0 and entry < 64 then
        shadow[entry][word_index + 1] = data & 0xffff
        local code, height_tiles, color, priority, hflip = decode_shadow(entry)
        writes:write(string.format(
            "%d,%06X,%d,%d,%04X,%04X,%04X,%d,%d,%d,%d\n",
            frame, offset, entry, word_index, data & 0xffff, mem_mask & 0xffff,
            code, height_tiles, color, priority, hflip
        ))
        writes:flush()
    end

    return data
end

local maincpu = manager.machine.devices[":maincpu"]
if maincpu ~= nil and maincpu.spaces["program"] ~= nil then
    _G.xybots_mob_capture.write_tap = maincpu.spaces["program"]:install_write_tap(0x802e00, 0x802fff, "xybots_mob_write_tap", on_mob_write)
    log:write("Installed write tap on :maincpu program 0x802e00-0x802fff.\n")
else
    log:write("Could not install write tap: :maincpu program space not found.\n")
end

_G.xybots_mob_capture.stop_sub = emu.add_machine_stop_notifier(function()
    log:write("\nStopped: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    log:write("Frames observed: " .. frame .. "\n")
    log:flush()
    csv:close()
    writes:close()
    log:close()
end)

print("Xybots MOB capture writing to " .. csv_path)
