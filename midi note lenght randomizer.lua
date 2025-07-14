-- @description Humanize MIDI note ends
-- @version 1.0
-- @changelog
-- v1.1 - English translation
-- @about
-- This script randomizes only the ends of MIDI notes while keeping the beginning temporally identical.
-- It allows you to select all or just some notes, adjust the intensity of the change, and generate a new seed for the randomization.
-- Hotkeys are 'Enter' to start the process and automatically close it, 'Esc' to exit, and 'r' or 'R' to regenerate the seed.
-- The window must be selected and a MIDI editor must be open for any interaction to work.
-- It works with tens of thousands of MIDI notes, but above half a million, processing starts to take more than 10 seconds.
-- The basic structure was provided by Claude.AI; the final code was modified and verified by me.
-- @license GPL-3.0


do
    local reaper = reaper
    
    -- Configuration
    local EXT_SECTION = "RandomNoteLength"
    local EXT_KEY_INTENSITY = "Intensity" 
    local EXT_KEY_APPLYALL = "ApplyAll"
    local EXT_KEY_SEED = "RandomSeed"
    
    -- Window dimensions
    local DEFAULT_WND_W = 400
    local DEFAULT_WND_H = 200
    local MIN_WND_W = 350
    local MIN_WND_H = 180
    
    -- Cache functions for performances
    local random = math.random
    local randomseed = math.randomseed
    local floor = math.floor
    local min, max = math.min, math.max
    local os_time = os.time
    local time_precise = reaper.time_precise
    local string_pack = string.pack
    local string_unpack = string.unpack
    local midi_ppq_to_time = reaper.MIDI_GetProjTimeFromPPQPos
    local midi_time_to_ppq = reaper.MIDI_GetPPQPosFromProjTime
    
    -- Global state
    local state = {
        intensity = tonumber(reaper.GetExtState(EXT_SECTION, EXT_KEY_INTENSITY)) or 0.5,
        applyToAllNotes = (reaper.GetExtState(EXT_SECTION, EXT_KEY_APPLYALL) ~= "0"),
        current_seed = os_time() + math.random(1000, 9999),
        last_execution_time = 0,
        last_notes_processed = 0,
        last_method_used = "N/A",
        dragging_slider = false,
        mouse_was_down = false,
        last_slider_click_time = 0,
        double_click_threshold = 0.3,
        seed_confirmation_time = 0,
        seed_confirmation_duration = 0.2,
        execute_confirmed = false,
        execute_confirmation_time = 0,
        execute_confirmation_duration = 0.2,
        auto_seed_cycles = 0,
        auto_seed_interval = 3
    }
    
    local layout = {}
    local percentage_cache = {}
    for i = 0, 100 do
        percentage_cache[i] = i .. "%"
    end
    
    randomseed(state.current_seed)
    reaper.SetExtState(EXT_SECTION, EXT_KEY_SEED, tostring(state.current_seed), true)
    
    -- Save settings
    local function saveSettings()
        reaper.SetExtState(EXT_SECTION, EXT_KEY_INTENSITY, tostring(state.intensity), true)
        reaper.SetExtState(EXT_SECTION, EXT_KEY_APPLYALL, state.applyToAllNotes and "1" or "0", true)
        reaper.SetExtState(EXT_SECTION, EXT_KEY_SEED, tostring(state.current_seed), true)
    end
    
    -- Generate new seed
    local function generateNewSeed()
        state.current_seed = os_time() + random(1000, 9999)
        randomseed(state.current_seed)
        state.seed_confirmation_time = time_precise()
        state.auto_seed_cycles = 0
        saveSettings()
    end
    
    -- Automatic seed regeneration in background
    local function checkAutoSeedRegeneration()
        state.auto_seed_cycles = state.auto_seed_cycles + 1
        if state.auto_seed_cycles >= state.auto_seed_interval then
            generateNewSeed()
        end
    end
    
    -- Main process for MIDI notes
    local function processNotes()
        local take = reaper.MIDIEditor_GetTake(reaper.MIDIEditor_GetActive())
        if not take then return end
        
        local start_time = time_precise()
        local intensity_val = state.intensity
        local apply_all = state.applyToAllNotes
        
        reaper.Undo_BeginBlock()
        
        -- Get all MIDI events
        local gotAllOK, MIDIstring = reaper.MIDI_GetAllEvts(take, "")
        if not gotAllOK then
            reaper.Undo_EndBlock("Randomizza fine note", 0)
            return
        end
        
        -- Identify all couples of note On/Off
        local note_pairs = {}
        local active_notes = {}
        local MIDIlen = MIDIstring:len()
        local positionInString = 1
        local modifications = 0
        local running_ppq = 0
        
        -- First pass: find all couples of note On/Off, method by @juliansader
        while positionInString < MIDIlen - 12 do
            local offset, flags, msg, newPos = string_unpack("i4Bs4", MIDIstring, positionInString)
            if not newPos or newPos <= positionInString then break end
            
            running_ppq = running_ppq + offset
            
            if msg and msg:len() >= 3 then
                local msg1 = msg:byte(1)
                if msg1 then
                    local eventType = msg1 >> 4
                    local channel = msg1 & 0x0F
                    local pitch = msg:byte(2)
                    local velocity = msg:byte(3)
                    local key = pitch .. "_" .. channel
                    
                    if eventType == 0x9 and velocity > 0 then -- Note On
                        local selected = (flags & 1 == 1)
                        
                        if not active_notes[key] then
                            active_notes[key] = {}
                        end
                        
                        table.insert(active_notes[key], {
                            start_ppq = running_ppq,
                            start_pos = positionInString,
                            selected = selected,
                            velocity = velocity
                        })
                        
                    elseif (eventType == 0x9 and velocity == 0) or eventType == 0x8 then -- Note Off
                        local note_off_selected = (flags & 1 == 1)
                        
                        if active_notes[key] and #active_notes[key] > 0 then
                            local note = table.remove(active_notes[key], 1)
                            local is_selected = note.selected or note_off_selected
                            
                            local pair = {
                                start_ppq = note.start_ppq,
                                end_ppq = running_ppq,
                                start_pos = note.start_pos,
                                end_pos = positionInString,
                                selected = is_selected,
                                pitch = pitch,
                                channel = channel,
                                velocity = note.velocity,
                                original_length = running_ppq - note.start_ppq,
                                key = key
                            }
                            
                            if pair.original_length <= 0 then
                                table.insert(note_pairs, pair)
                            elseif (apply_all or pair.selected) and pair.original_length > 1 then
                                local max_variation = pair.original_length * intensity_val
                                local variation = (random() * 2 - 1) * max_variation
                                pair.new_length = max(1, floor(pair.original_length + variation + 0.5))
                                local start_time = reaper.MIDI_GetProjTimeFromPPQPos(take, pair.start_ppq)
                                local end_time = reaper.MIDI_GetProjTimeFromPPQPos(take, pair.end_ppq)
                                local original_duration_seconds = end_time - start_time
                                local max_variation_seconds = original_duration_seconds * intensity_val
                                local variation_seconds = (random() * 2 - 1) * max_variation_seconds
                                local new_end_time = end_time + variation_seconds
                                pair.new_end_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, new_end_time)
                                pair.new_length = pair.new_end_ppq - pair.start_ppq
                                pair.new_end_ppq = pair.start_ppq + pair.new_length
                                modifications = modifications + 1
                            else
                                pair.new_end_ppq = pair.end_ppq
                                pair.new_length = pair.original_length
                            end
                            
                            table.insert(note_pairs, pair)
                        end
                    end
                end
            end
            
            positionInString = newPos
        end
        
        -- Rebuild MIDI string with modifications
        if modifications > 0 then
            local pos_to_new_ppq = {}
            for _, pair in ipairs(note_pairs) do
                if pair.new_end_ppq ~= pair.end_ppq then
                    pos_to_new_ppq[pair.end_pos] = pair.new_end_ppq
                end
            end
            
            local events_to_process = {}
            positionInString = 1
            running_ppq = 0
            
            while positionInString < MIDIlen - 12 do
                local offset, flags, msg, newPos = string_unpack("i4Bs4", MIDIstring, positionInString)
                if not newPos or newPos <= positionInString then break end
                
                running_ppq = running_ppq + offset
                local final_ppq = running_ppq
                
                if pos_to_new_ppq[positionInString] then
                    final_ppq = pos_to_new_ppq[positionInString]
                end
                
                table.insert(events_to_process, {
                    ppq = final_ppq,
                    flags = flags,
                    msg = msg
                })
                
                positionInString = newPos
            end
            
            table.sort(events_to_process, function(a, b)
                return a.ppq < b.ppq
            end)
            
            local new_events = {}
            local previous_ppq = 0
            
            for i, event in ipairs(events_to_process) do
                local delta_offset = event.ppq - previous_ppq
                if delta_offset < 0 then delta_offset = 0 end
                
                -- Fix: Convert delta_offset to integer
                delta_offset = floor(delta_offset + 0.5)
                
                new_events[i] = string_pack("i4Bs4", delta_offset, event.flags, event.msg)
                previous_ppq = event.ppq
            end
            
            local newMIDIstring = table.concat(new_events) .. MIDIstring:sub(-12)
            reaper.MIDI_SetAllEvts(take, newMIDIstring)
            reaper.MIDI_Sort(take)
        end
        
        reaper.Undo_EndBlock("Randomizza fine note", modifications > 0 and -1 or 0)
        
        local end_time = time_precise()
        state.last_execution_time = end_time - start_time
        state.last_notes_processed = modifications
        state.last_method_used = "Standard"
        
        -- Automatic seed regeneration
        checkAutoSeedRegeneration()
    end
    
    -- Equivalence to old process
    local function processNotesAdaptive()
        processNotes()
    end
    
    -- Update responsive layout
    local function updateLayout()
        local W, H = gfx.w, gfx.h
        
        if W < MIN_WND_W then W = MIN_WND_W end
        if H < MIN_WND_H then H = MIN_WND_H end
        
        local scale_x = W / DEFAULT_WND_W
        local scale_y = H / DEFAULT_WND_H
        local scale = math.min(scale_x, scale_y)
        
        local margin = math.max(10, 15 * scale)
        local spacing = 15 * scale_y
        
        layout.font_size = math.max(12, math.floor(16 * scale))
        layout.font_size_small = math.max(10, math.floor(12 * scale))
        layout.scale_x = scale_x
        layout.scale_y = scale_y
        layout.scale = scale
        
        layout.radio_y = margin + 7.5 * scale_y
        layout.radio_size = math.max(10, 14 * scale)
        layout.radio1_x = margin
        layout.radio2_x = margin + (160 * scale_x)
        
        layout.intensity_y = margin + 45 * scale_y
        layout.intensity_label_w = 60 * scale_x
        layout.slider_w = math.max(120, (W - margin * 2 - layout.intensity_label_w - 60 * scale_x))
        layout.slider_h = math.max(20, 25 * scale)
        layout.slider_x = margin + layout.intensity_label_w
        layout.percentage_x = layout.slider_x + layout.slider_w + (10 * scale_x)
        
        layout.btn_h = math.max(24, 30 * scale)
        layout.btn_y = layout.intensity_y + layout.slider_h + spacing
        layout.seed_btn_w = math.max(120, 150 * scale_x)
        layout.seed_btn_x = margin
        layout.execute_btn_w = math.max(70, 85 * scale_x)
        layout.execute_btn_x = W - margin - layout.execute_btn_w
        
        layout.info_box_y = layout.btn_y + layout.btn_h + spacing
        layout.info_box_w = W - margin * 2
        layout.info_box_h = layout.font_size_small + 12 * scale_y
        layout.info_box_x = margin
    end
    
    -- Draw GUI, inspired by Reaper's native Humanizer
    local function drawGUI()
        local W, H = gfx.w, gfx.h
        updateLayout()
        
        gfx.set(0.96, 0.96, 0.96)
        gfx.rect(0, 0, W, H)
        
        gfx.setfont(1, "Segoe UI", layout.font_size)
        
        -- Radio buttons
        local radio_size = layout.radio_size
        
        gfx.set(1, 1, 1)
        gfx.circle(layout.radio1_x + radio_size/2, layout.radio_y + radio_size/2, radio_size/2, 1)
        gfx.set(0.3, 0.3, 0.3)
        gfx.circle(layout.radio1_x + radio_size/2, layout.radio_y + radio_size/2, radio_size/2, 0)
        
        if state.applyToAllNotes then
            gfx.set(0.2, 0.6, 1.0)
            gfx.circle(layout.radio1_x + radio_size/2, layout.radio_y + radio_size/2, radio_size/4, 1)
        end
        
        gfx.set(0.1, 0.1, 0.1)
        gfx.x = layout.radio1_x + radio_size + 8
        gfx.y = layout.radio_y + (radio_size - layout.font_size)/2
        gfx.drawstr("All notes")
        
        gfx.set(1, 1, 1)
        gfx.circle(layout.radio2_x + radio_size/2, layout.radio_y + radio_size/2, radio_size/2, 1)
        gfx.set(0.3, 0.3, 0.3)
        gfx.circle(layout.radio2_x + radio_size/2, layout.radio_y + radio_size/2, radio_size/2, 0)
        
        if not state.applyToAllNotes then
            gfx.set(0.2, 0.6, 1.0)
            gfx.circle(layout.radio2_x + radio_size/2, layout.radio_y + radio_size/2, radio_size/4, 1)
        end
        
        gfx.set(0.1, 0.1, 0.1)
        gfx.x = layout.radio2_x + radio_size + 8
        gfx.y = layout.radio_y + (radio_size - layout.font_size)/2
        gfx.drawstr("Selected notes")
        
        -- Intensity slider
        gfx.set(0.1, 0.1, 0.1)
        gfx.x = layout.radio1_x
        gfx.y = layout.intensity_y + (layout.slider_h - layout.font_size)/2
        gfx.drawstr("Intensity:")
        
        gfx.set(0.85, 0.85, 0.85)
        gfx.rect(layout.slider_x, layout.intensity_y, layout.slider_w, layout.slider_h)
        gfx.set(0.7, 0.7, 0.7)
        gfx.rect(layout.slider_x, layout.intensity_y, layout.slider_w, 2)
        gfx.rect(layout.slider_x, layout.intensity_y + layout.slider_h - 2, layout.slider_w, 2)
        
        -- Tick marks
        local segments = 10
        for i = 1, segments - 1 do
            local x = layout.slider_x + (layout.slider_w * i / segments)
            gfx.set(0.7, 0.7, 0.7)
            gfx.line(x, layout.intensity_y + layout.slider_h - 8, x, layout.intensity_y + layout.slider_h - 2)
        end
        
        -- Transparent center line (50%)
        local center_x = layout.slider_x + layout.slider_w / 2
        gfx.set(0.4, 0.4, 0.4, 0.0)
        gfx.line(center_x, layout.intensity_y + 2, center_x, layout.intensity_y + layout.slider_h - 2)
        
        local handle_w = math.max(14, 18 * (layout.slider_h / 25))
        local handle_x = layout.slider_x + state.intensity * (layout.slider_w - handle_w)
        gfx.set(1, 1, 1)
        gfx.rect(handle_x, layout.intensity_y, handle_w, layout.slider_h)
        gfx.set(0.2, 0.2, 0.2)
        gfx.rect(handle_x, layout.intensity_y, handle_w, layout.slider_h, 0)
        gfx.rect(handle_x + 1, layout.intensity_y + 1, handle_w - 2, layout.slider_h - 2, 0)
        
        gfx.set(0.1, 0.1, 0.1)
        gfx.x = layout.percentage_x
        gfx.y = layout.intensity_y + (layout.slider_h - layout.font_size)/2
        local percent_idx = floor(state.intensity * 100 + 0.5)
        gfx.drawstr(percentage_cache[percent_idx])
        
        -- Buttons
        local current_time = time_precise()
        local seed_active = (current_time - state.seed_confirmation_time) < state.seed_confirmation_duration
        local execute_active = state.execute_confirmed and (current_time - state.execute_confirmation_time) < state.execute_confirmation_duration
        
        gfx.set(1, 1, 1)
        gfx.rect(layout.seed_btn_x, layout.btn_y, layout.seed_btn_w, layout.btn_h)
        if seed_active then
            gfx.set(0.2, 0.6, 1.0)
        else
            gfx.set(0.3, 0.3, 0.3)
        end
        gfx.rect(layout.seed_btn_x, layout.btn_y, layout.seed_btn_w, layout.btn_h, 0)
        if seed_active then
            gfx.set(0.5, 0.8, 1.0)
            gfx.rect(layout.seed_btn_x + 1, layout.btn_y + 1, layout.seed_btn_w - 2, layout.btn_h - 2, 0)
        end
        
        gfx.set(0.1, 0.1, 0.1)
        local seed_text = "New random seed"
        local text_w, text_h = gfx.measurestr(seed_text)
        gfx.x = layout.seed_btn_x + (layout.seed_btn_w - text_w)/2
        gfx.y = layout.btn_y + (layout.btn_h - text_h)/2
        gfx.drawstr(seed_text)
        
        gfx.set(1, 1, 1)
        gfx.rect(layout.execute_btn_x, layout.btn_y, layout.execute_btn_w, layout.btn_h)
        if execute_active then
            gfx.set(0.2, 0.6, 1.0)
        else
            gfx.set(0.3, 0.3, 0.3)
        end
        gfx.rect(layout.execute_btn_x, layout.btn_y, layout.execute_btn_w, layout.btn_h, 0)
        if execute_active then
            gfx.set(0.5, 0.8, 1.0)
            gfx.rect(layout.execute_btn_x + 1, layout.btn_y + 1, layout.execute_btn_w - 2, layout.btn_h - 2, 0)
        end
        
        gfx.set(0.1, 0.1, 0.1)
        local exec_text = "RUN"
        local exec_w, exec_h = gfx.measurestr(exec_text)
        gfx.x = layout.execute_btn_x + (layout.execute_btn_w - exec_w)/2
        gfx.y = layout.btn_y + (layout.btn_h - exec_h)/2
        gfx.drawstr(exec_text)
        
        -- Statistics box
        if state.last_execution_time > 0 then
            gfx.set(0.98, 0.98, 0.98)
            gfx.rect(layout.info_box_x, layout.info_box_y, layout.info_box_w, layout.info_box_h)
            gfx.set(0.9, 0.9, 0.9)
            gfx.rect(layout.info_box_x, layout.info_box_y, layout.info_box_w, layout.info_box_h, 0)
            gfx.rect(layout.info_box_x + 1, layout.info_box_y + 1, layout.info_box_w - 2, layout.info_box_h - 2, 0)
            
            gfx.setfont(2, "Segoe UI", layout.font_size_small)
            
            local info_y = layout.info_box_y + 6 * layout.scale_y
            
            gfx.set(0.1, 0.1, 0.1)
            gfx.x, gfx.y = layout.info_box_x + 8, info_y
            local stats_text = "Statistics: " .. string.format("%.3f", state.last_execution_time) .. "s"
            if state.last_notes_processed > 0 then
                local speed = state.last_notes_processed / state.last_execution_time
                stats_text = stats_text .. " | " .. tostring(state.last_notes_processed) .. " note(s) | " .. string.format("%.0f", speed) .. "/s"
            end
            gfx.drawstr(stats_text)
        end
    end
    
    -- Check if point is inside rectangle
    local function isInRect(x, y, rx, ry, rw, rh)
        return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
    end
    
    -- Handle input mouse
    local function handleMouse()
        local mx, my = gfx.mouse_x, gfx.mouse_y
        local mouse_down = gfx.mouse_cap & 1 == 1
        local current_time = time_precise()
        
        if mouse_down and not state.mouse_was_down then
            local radio_size = layout.radio_size
            if isInRect(mx, my, layout.radio1_x, layout.radio_y, 120, radio_size + 4) then
                state.applyToAllNotes = true
            elseif isInRect(mx, my, layout.radio2_x, layout.radio_y, 140, radio_size + 4) then
                state.applyToAllNotes = false
            elseif isInRect(mx, my, layout.slider_x, layout.intensity_y, layout.slider_w, layout.slider_h) then
                -- Check double click on slider
                if (current_time - state.last_slider_click_time) < state.double_click_threshold then
                    state.intensity = 0.5
                else
                    state.dragging_slider = true
                    local val = (mx - layout.slider_x) / layout.slider_w
                    state.intensity = math.max(0, math.min(1, val))
                end
                state.last_slider_click_time = current_time
            elseif isInRect(mx, my, layout.seed_btn_x, layout.btn_y, layout.seed_btn_w, layout.btn_h) then
                generateNewSeed()
            elseif isInRect(mx, my, layout.execute_btn_x, layout.btn_y, layout.execute_btn_w, layout.btn_h) then
                state.execute_confirmation_time = time_precise()
                state.execute_confirmed = true
                processNotesAdaptive()
            end
        elseif mouse_down and state.dragging_slider then
            local val = (mx - layout.slider_x) / layout.slider_w
            state.intensity = math.max(0, math.min(1, val))
        elseif not mouse_down then
            state.dragging_slider = false
        end
        
        state.mouse_was_down = mouse_down
    end
    
    -- Main loop of the interface
    local function mainLoop()
        local char = gfx.getchar()
        if char < 0 or char == 27 then  -- ESC to close
            saveSettings()
            gfx.quit()
            return
        end
        
        if char == 13 then  -- Enter/return to execute and close
            -- Visual feedback
            state.execute_confirmation_time = time_precise()
            state.execute_confirmed = true
            processNotesAdaptive()
            
            -- Close automatically after this specific execution
            saveSettings()
            gfx.quit()
            return
        end

        if char == 114 or char == 82 then  -- 'r' o 'R' to regenerate a new seed
            generateNewSeed()
        end
        
        handleMouse()
        drawGUI()
        
        reaper.defer(mainLoop)
    end
    
    -- Initialize and start GUI
    if gfx.init("Humanize MIDI note ends", DEFAULT_WND_W, DEFAULT_WND_H, 1) then
        gfx.dock(0)
        mainLoop()
    else
        reaper.ShowMessageBox("Error initializing GUI", "Error", 0)
    end
end



