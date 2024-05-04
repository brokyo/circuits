-- Circuits
-- awakening.systems
--
-- Two phase polyphonic trackers
-- with per-step timing configuration
--
-- Rows are in-scale notes
-- Columns are steps
-- Supports n.b voices
-- 
-- |Quickstart|
-- Grid to program trackers
-- Lower left sets octave
-- Row 8 selects active tracker
-- Row 7 starts/stops tracker
-- Rows 6 & 5 select phase to edit
--
-- |UI|
-- E2 scrolls list, E3 changes values
-- "Menu" changes between config pages
-- 
-- |Step Editing Key Combo|
-- Hold tracker button and press step to jump
-- to that step's edit page

--------------------
-- Core libraries --
--------------------
local nb = require("circuits/lib/nb/lib/nb")
local musicutil = require "musicutil"
local lattice = require "lattice"
local g = grid.connect()

--------------------
-- Configuration  --
--------------------
-- Timbre
local scale_names = {} -- Table to hold scale names so they can be listed as strings
local scale_index = 1
local tonic_index = 1

-- Global State Management
local active_tracker_index = 1 -- Working tracker on norns and grid
local active_phase_index = 1 -- Working phase on norns and grid

-- Global Tracker Management
local max_steps = 12

-- UI 
-- UI > Index for nav/data
local active_ui_pane = 1 -- Determines which norns pane is active. Controlled by k2 and k3
local active_window_start = 1 -- Manage the editable window on the grid 
local active_config_index = 1 -- Manage the config view & retrieve relevant data
local config_selected_param = 1 -- Track selected parameter for setting screen.light
local selected_step = 1 -- Individual step to edit

-- UI > Navigation View
local app_mode_index = 3
local navigation_selected_param = 1
local navigation_parms_names = {
    "wave",
    "config"
}
local navigation_params_values = {
    active_tracker_index,
    active_phase_index
}

-- UI > Global View
local global_param_names = {
    {
        "Mode",
        "Key",
        "Tempo"
    }
}

-- UI > Config View
local param_names_table = {
    -- Wave
    {
        "Menu",
        "Clock Mod",
        "Total Phases",
        "Phase 1 Cycles",
        "Phase 2 Cycles",
        "Beats To Sleep"
    },
    -- Loop
    {
        "Menu",
        "Voice",
        "Octave",
        "Grid Oct Shift",
    },
    -- Step
    {
        "Menu",
        "Step", 
        "Velocity", 
        "Swing", 
        "Division", 
        "Beats Sus"
    }
}

-- UI > Keyboard view
local keyboard_param_names = {
    {
        "Voice",
        "Root Oct",
        "String Dist",
        "Vel Root"
    }
}

local keyboard_voice_index = 0
local keyboard_root_octave = 2
local keyboard_string_distance = 5
local velocity_root = 0.6
local velocity = 0.6

-- UI > Naming maps
local config_options = {"Wave", "Voice", "Step"} -- Naming config pages for UI
local division_options = {1/16, 1/8, 1/4, 1/3, 1/2, 2/3, 1, 2, 4, 8, 12} -- Possible step divisions
local division_option_names = {"1/16", "1/8", "1/4", "1/3", "1/2", "2/3", "1", "2", "4", "8", "12"} -- Names as strings for showing in param list
local clock_modifider_options = {8, 4, 2, 1, 1/2, 1/4, 1/8} -- Multiplied to duration selection to set wave-wide clock modifications
local clock_modifider_options_names = {"/8", "/4", "/2", "x1", "x2", "x4", "x8"}
local octave_on_grid = 0 -- the octave that appears on the grid

-- UI > Scrolling Controls
local scroll_index = 1 -- Track the first visible item in a long list
local max_items_on_screen = 6 

-- Grid
-- Grid > lighting 
local inactive_light = 2
local dim_light = 3
local medium_light = 8
local high_light = 10
local max_light = 15

-- Grid > control panel locations
local CONTROL_COLUMNS_START = 13
local CONTROL_COLUMNS_END = 16
local MINIMAP_START_ROW = 1
local MINIMAP_END_ROW = 3
local TRACKER_FALLING_ROW = 5
local TRACKER_RISING_ROW = 6
local PLAYBACK_STATUS_ROW = 7
local TRACKER_SELECTION_ROW = 8

-- Grid > keycombo catcher
local key_states = {
    tracker_selection = {},
    minimap = {}
}

---------------------------
-- Trackers and Playback --
---------------------------

-- Trackers > Global references for core tables
local nb_voices = {} -- Table for referencing n.b voices
local trackers = {} -- Table for referencing trackers
local sequencers = {}
local primary_lattice = lattice:new()

function create_tracker(voice_id, root_octave) -- Create trackers and set defaults
    local tracker = {
        -- Voice Config
        voice_id = voice_id,
        voice_index = 1,
        root_octave = root_octave,
        -- Playback Config
        playing = false,
        clock_modifider = 1,
        beats_to_rest = 0,
        -- Playback Indexes
        current_position = 1,
        current_phase = 1,
        total_phases = 1,
        -- Playback Phases
        phases = {
            {
                steps = {},
                length = max_steps,
                current_cycle = 1,
                total_cycles = 2
            },
            {
                steps = {},
                length = max_steps,
                current_cycle = 1,
                total_cycles = 2
            }
        }
    }
    
    -- Initialize steps with default values
    for i = 1, max_steps do
        table.insert(tracker.phases[1].steps, {degrees = {}, velocity = 0.9, swing = 50, division = 1/4, duration = 1})
        table.insert(tracker.phases[2].steps, {degrees = {}, velocity = 0.9, swing = 50, division = 1/4, duration = 1})
    end
    
    return tracker
end

function build_scale(root_octave) -- Helper function for building scales from root note and mode set in settings
    local root_note = ((root_octave - 1) * 12) + tonic_index - 1 -- Get the MIDI note for one octave below the root. Adjust by 1 due to Lua indexing
    local scale = musicutil.generate_scale(root_note, scale_index, 3)
 
    return scale
end

function create_sequencers()
    for i = 1, #trackers do
        local tracker = trackers[i] -- Create an alias for convenience
        tracker.voice_id = i -- Assign an id to the tracker voice so we can manage it with n.b elsewhere
        
        sequencers[i] = primary_lattice:new_sprocket{
            action = function()
                if tracker.playing then -- Check if the tracker is playing
                    redraw()
                    grid_redraw()
                    local current_phase = tracker.phases[tracker.current_phase] -- Get the active phase
                    -- Write some convenience Variables
                    local current_step = current_phase.steps[tracker.current_position] -- Get the table at the current step to configure play event
                    local degree_table = current_step.degrees -- Get the table of degrees to play for this step
                    local scale_notes = build_scale(tracker.root_octave) -- Generate a scale based on global key and mode
                    local modified_division = tracker.clock_modifider * current_step.division
                    local modified_duration = (tracker.clock_modifider * current_step.duration) - 0.05
                    -- print('S: ' .. tracker.current_position .. ' P: ' .. tracker.current_phase .. ' C: ' .. current_phase.current_cycle)
                    
                    -- Set modifiers for event
                    sequencers[i]:set_division(modified_division) -- Set the division for the current step
                    sequencers[i]:set_swing(current_step.swing) -- Set the swing for the current step
                    
                    -- Schedule note
                    if #degree_table > 0 then -- Check to see if the degree table at the current step contains values
                        for _, degree in ipairs(degree_table) do  -- If it does is, iterate through each degree
                            local note = scale_notes[degree] -- And match it to the appropriate note in the scale
                            local player = params:lookup_param("voice_" .. i):get_player() -- Get the n.b voice
                            player:play_note(note, current_step.velocity, modified_duration) -- And play the note
                        end
                    end
                    
                    tracker.current_position = tracker.current_position + 1 -- Increment the position
                    if tracker.current_position == current_phase.length + 1 then -- If we've increased beyond the length
                    -- print('Ended:' .. ' P: ' .. tracker.current_phase .. ' C: ' .. current_phase.current_cycle)

                        current_phase.current_cycle = current_phase.current_cycle + 1 -- Increase the cycle count
                        tracker.current_position = 1 -- Reset the position

                        if current_phase.current_cycle == current_phase.total_cycles + 1 then -- If we're beyond the cycle limit, switch the phase
                            if tracker.total_phases == 1 then -- If this tracker doesn't have phases
                                current_phase.current_cycle = 1 -- Reset the cycle counter (cycle counter doesn't matter with a single phase. This is hygeine)
                            else -- Otherwise
                                tracker.current_phase = (tracker.current_phase + 1) % 3 -- Increment the phase tracker

                                if tracker.current_phase == 0 then
                                    sequencers[i]:set_division(tracker.beats_to_rest) -- Sleep the tracker until this number of beats pass
                                    tracker.current_phase = 1 -- Reset the phase
                                    current_phase.current_cycle = 1  -- Reset the cycle
                                else
                                    current_phase.current_cycle = 1
                                end
                            end
                        end
                    end
                end
            end,
            division = 1
        }
    end
end

--------------------
-- Grid Functions --
--------------------
-- Logic to update the length of the active tracker (i.e the number of steps that will play of the possible 24)
function update_tracker_length(x, y)
    -- Check if any tracker selection key is pressed
    local any_tracker_selection_key_pressed = false
    for _, is_pressed in pairs(key_states.tracker_selection) do
        if is_pressed then
            any_tracker_selection_key_pressed = true
            break
        end
    end

    -- Only update tracker length if no tracker selection key is pressed
    if not any_tracker_selection_key_pressed then
        local length_offset = ((y - MINIMAP_START_ROW) * 4) + (x - CONTROL_COLUMNS_START + 1)
        trackers[active_tracker_index].phases[active_phase_index].length = length_offset

        -- Catch edge case where the length is changed to be shorter than the current position
        if trackers[active_tracker_index].current_position > trackers[active_tracker_index].phases[active_phase_index].length then
            trackers[active_tracker_index].current_position = 1
        end
        grid_redraw()
        redraw()
    end
end

function step_edit_shortcut(tracker_index, minimap_key)
    if minimap_key == nil then return end -- Exit function if there's no minimap_key pressed
    active_config_index = 4
    active_tracker_index = tracker_index
    selected_step = minimap_key
    redraw()
end

-- TODO: Figure out where this happens
-- Logic to change playback state
function toggle_tracker_playback(tracker_index)
    local tracker_to_change = trackers[tracker_index]
    tracker_to_change.playing = not tracker_to_change.playing -- Flip the playback status
    -- And reset position to zero if we're stopping
    if not tracker_to_change.playing then
        tracker_to_change.current_position = 1
        tracker_to_change.current_phase = 1
    end
    redraw()
    grid_redraw()
end

-- Logic for handling key pressed on the control panel (columns 13 > 16)
function handle_control_column_press(x, y, pressed)
    -- Update key_states table to handle keycombo
    if y == TRACKER_SELECTION_ROW then
        key_states.tracker_selection[x - CONTROL_COLUMNS_START + 1] = (pressed == 1)
    elseif y >= MINIMAP_START_ROW and y <= MINIMAP_END_ROW then
        key_states.minimap[(y - MINIMAP_START_ROW) * 4 + (x - CONTROL_COLUMNS_START + 1)] = (pressed == 1)
    end

    if pressed == 0 then return end -- Ignore key releases

    if y == TRACKER_SELECTION_ROW then -- Change active tracker by pressing corresponding key (ALT: handle keycombo for editing shortcut)
        local selected_tracker = x - CONTROL_COLUMNS_START + 1
        if selected_tracker == active_tracker_index then -- Enable editing shortcut if this is already the active tracker
            step_edit_shortcut(selected_tracker)
        else
            change_active_tracker(selected_tracker) -- Otherwise change the tracker
        end
    elseif y >= MINIMAP_START_ROW and y <= MINIMAP_END_ROW then -- Change tracker length by pressing final step
        update_tracker_length(x, y)
    elseif y >= TRACKER_FALLING_ROW and y<= TRACKER_RISING_ROW then
        change_working_phase(x - CONTROL_COLUMNS_START + 1, y)
    elseif y == PLAYBACK_STATUS_ROW then -- Toggle playback status
        toggle_tracker_playback(x - CONTROL_COLUMNS_START + 1)
    end

    -- Check for key combination after updating states
    for tracker_index, is_pressed in pairs(key_states.tracker_selection) do
        if is_pressed then
            for step_index, is_minimap_pressed in pairs(key_states.minimap) do
                if is_minimap_pressed then
                    -- Call the function to jump to the step edit mode for the selected step
                    step_edit_shortcut(tracker_index, step_index)
                    return -- Exit early to avoid processing other keys
                end
            end
        end
    end
end

-- Logic for changing the octave on the grid to allow the user to play across three octaves
function hanlde_octave_change(x, y, pressed)
    if pressed == 0 then return end -- Ignore key releases

    if x == 1 then
        octave_on_grid = -1
        redraw()
        grid_redraw()
    elseif x == 2 then
        octave_on_grid = 0
        redraw()
        grid_redraw()
    elseif x == 3 then
        octave_on_grid = 1
        redraw()
        grid_redraw()
    end
end

function handle_grid_keys_tracker(x, y, pressed)
    if x >= CONTROL_COLUMNS_START and x <= CONTROL_COLUMNS_END then
        handle_control_column_press(x, y, pressed)
    elseif y == 8 then
        hanlde_octave_change(x, y, pressed)
    else
        local working_tracker = trackers[active_tracker_index]
        local working_phase = working_tracker.phases[active_phase_index]
        local adjusted_x = x + active_window_start - 1

        -- Invert y-coordinate to match the horizontal layout and adjust for octave_on_grid
        local degree = ((octave_on_grid + 1) * 7) + (8 - y) -- Inverting y by using (9 - y)

        if pressed == 1 and adjusted_x <= 21 then
            local index = nil
            for i, v in ipairs(working_phase.steps[adjusted_x].degrees) do
                if v == degree then
                    index = i
                    break
                end
            end
            if index then
                table.remove(working_phase.steps[adjusted_x].degrees, index)
                print("Degree " .. degree .. " removed from step " .. adjusted_x .. " in phase " .. active_phase_index)
            else
                table.insert(working_phase.steps[adjusted_x].degrees, degree)
                print("Degree " .. degree .. " added to step " .. adjusted_x .. " in phase " .. active_phase_index)
            end
            grid_redraw()
        end
    end
end

--------------------
-- Keyboard Stuff --
--------------------
local keyboard_min_octave = 1
local clonky_active = {}
local current_velocity_index = 1

function get_keyboard_config_values()
    return {
        {
            tostring(nb_voices[keyboard_voice_index]),
            tostring(keyboard_root_octave),
            tostring(keyboard_string_distance),
            tostring(velocity_root)
        }
    }
end

function draw_clonky()
    for x = 1, 8 do
        for y = 1, 8 do
            g:led(x, y, dim_light)
        end
    end

    for note, coords in pairs(clonky_active) do
        g:led(coords.x, coords.y, high_light)
    end

    g:led(9, current_velocity_index, high_light)
end

-- TODO: Better to just create the scale once then update when needed. Quickest version while testing the idea.
function get_midi_note_from_keyboard(x, y)
    local octave_offset = keyboard_min_octave * 12
    local scale = musicutil.generate_scale_of_length(((tonic_index - 1)) + (12 * keyboard_root_octave), scale_index, 80) 
    local note_index = (8 - y) + ((x - 1) * keyboard_string_distance) + 1
    return scale[note_index]
end

function handle_grid_keys_clonky(x, y, pressed)
    if x <= 8 then
        local midi_note = get_midi_note_from_keyboard(x, y)
        local player = params:lookup_param("keyboard_voice"):get_player()

        if pressed == 1 then
            -- TODO: Set velocity elsewhere on grid, default to 0.9 if no selection
            player:note_on(midi_note, velocity)
            print("Note on: " .. midi_note, velocity)
            clonky_active[midi_note] = {x = x, y = y}  -- Store active note with its grid coordinates
        else
            player:note_off(midi_note)
            print("Note off: " .. midi_note)
            clonky_active[midi_note] = nil  -- Remove note from active list when released
        end
    elseif x == 9 then
        current_velocity_index = y
        velocity = velocity_root + (0.05 * (8 - y))
    end

    grid_redraw()
end

function g.key(x, y, pressed)    
    if app_mode_index == 1 then
    elseif app_mode_index == 2 then
        handle_grid_keys_tracker(x, y, pressed)
    elseif app_mode_index == 3 then
        handle_grid_keys_clonky(x, y, pressed)
    end
end

------------------------------
-- Shared Global Functions --
------------------------------
 
-- Logic for changing the active tracker
function change_active_tracker(new_tracker_index)
    active_tracker_index = new_tracker_index
    octave_on_grid = 0 -- Reset the grid to the new tracker's root
    grid_redraw()
    redraw()
end

function change_active_phase(new_phase_index)
    active_phase_index = new_phase_index
    octave_on_grid = 0
    grid_redraw()
    redraw()
end

-- Select the tracker and phase 
function change_working_phase(new_tracker_index, new_phase_row)
    active_config_index = 2
    active_phase_index = 7 - new_phase_row
    active_tracker_index = new_tracker_index
    octave_on_grid = 0 -- Reset the grid to the new tracker's root
    grid_redraw()
    redraw()
end


------------------
-- UI Functions --
------------------
function change_active_config(new_config_index)
    active_config_index = new_config_index
    grid_redraw()
    redraw()
end

function get_global_config_values()
    return {
        {
            tostring(scale_names[scale_index]),
            tostring(musicutil.NOTE_NAMES[tonic_index]),
            tostring(params:get('clock_tempo'))
        }
    }
end

function get_param_values_table() -- Returns a refresehed table of all param values
    local active_tracker = trackers[active_tracker_index]
    local active_phase = active_tracker.phases[active_phase_index]
    return {
        {
            config_options[active_config_index],
            tostring(clock_modifider_options_names[index_of(clock_modifider_options, trackers[active_tracker_index].clock_modifider)]),
            tostring(active_tracker.total_phases),
            tostring(active_tracker.phases[1].total_cycles),
            tostring(active_tracker.phases[2].total_cycles),
            tostring(active_tracker.beats_to_rest)
        },
        {
            config_options[active_config_index],
            tostring(nb_voices[trackers[active_tracker_index].voice_index]),
            tostring(trackers[active_tracker_index].root_octave),
            tostring(octave_on_grid),
        },
        {
            config_options[active_config_index],
            tostring(selected_step), 
            tostring(trackers[active_tracker_index].phases[active_phase_index].steps[selected_step].velocity), 
            tostring(trackers[active_tracker_index].phases[active_phase_index].steps[selected_step].swing), 
            division_option_names[index_of(division_options, trackers[active_tracker_index].phases[active_phase_index].steps[selected_step].division)], 
            division_option_names[index_of(division_options, trackers[active_tracker_index].phases[active_phase_index].steps[selected_step].duration)]
        }
    }
end


-- Physical Controls
function key(n, z)

    if n == 3 and z == 1 then -- K3 switches app mode
        app_mode_index = (app_mode_index % 3) + 1
        grid_redraw()
        redraw()
    end
end

function enc(n, d)
    -- For convenience
    -- TODO: Could make a global getter setter on these? But that feels like Engineering?
    local active_tracker = trackers[active_tracker_index]
    local active_phase = active_tracker.phases[active_phase_index]

    -- Encoder 1 adjusts the active window start in all modes
    if n == 1 then 
        -- active_window_start = util.clamp(active_window_start + d, 1, 13) -- Ensures the window doesn't go beyond the steps. Adjusts up to step 13 to allow a full window of 12 steps.
        -- grid_redraw()
    end

    ------------------------------------
    -- Global Config |  Encoder Logic --
    ------------------------------------
    if app_mode_index == 1 then
        if n == 2 then
            config_selected_param = util.clamp(config_selected_param + d, 1, #global_param_names[1]) -- Parameters: Mode, Key, Tempo, Section        
        elseif n == 3 then
            if config_selected_param == 1 then
                scale_index = util.clamp(scale_index + d, 1, #scale_names)
            elseif config_selected_param == 2 then
                tonic_index = util.clamp(tonic_index + d, 1, #musicutil.NOTE_NAMES)
            elseif config_selected_param == 3 then
                params:delta("clock_tempo",d)
            end
        end
    end

    ---------------------------------
    -- Tracker Config | Encoder Logic --
    ---------------------------------
    if app_mode_index == 2 then
        ----------
        -- Wave --
        ----------
        if active_config_index == 1 then
            if n == 2 then
                config_selected_param = util.clamp(config_selected_param + d, 1, #param_names_table[1]) -- Parameters: Clock modifier, Phase Count, Rising Cycle, Falling Cycles, Beats to Sleep
            elseif n == 3 then
                if config_selected_param == 1 then
                    active_config_index = util.clamp(active_config_index + d, 1, #config_options)
                elseif config_selected_param == 2 then
                    local current_mod_index = index_of(clock_modifider_options, trackers[active_tracker_index].clock_modifider)
                    local new_clock_mod_index = util.clamp(current_mod_index + d, 1, #clock_modifider_options)
                    trackers[active_tracker_index].clock_modifider = clock_modifider_options[new_clock_mod_index]           
                elseif config_selected_param == 3 then
                    local total_phases = active_tracker.total_phases
                    local phase_count = util.clamp(total_phases + d, 1, 2)
                    active_tracker.total_phases = phase_count                    
                elseif config_selected_param == 4 then
                    local phase_cycles = active_tracker.phases[1].total_cycles
                    local phase_count = util.clamp(phase_cycles + d, 1, 4)
                    active_tracker.phases[1].total_cycles = phase_count
                elseif config_selected_param == 5 then
                    local phase_cycles = active_tracker.phases[2].total_cycles
                    local phase_count = util.clamp(phase_cycles + d, 1, 4)
                    active_tracker.phases[2].total_cycles = phase_count
                elseif config_selected_param == 6 then
                    local beats_to_rest = active_tracker.beats_to_rest
                    local beat_count = util.clamp(beats_to_rest + d, 0, 4)
                    active_tracker.beats_to_rest = beat_count
                end
            end
        -----------
        -- Voice --
        -----------
        elseif active_config_index == 2 then
            if n == 2 then 
                config_selected_param = util.clamp(config_selected_param + d, 1, #param_names_table[2]) -- Parameters: Voice, Root Octave, Octave On Grid
            elseif n == 3 then
                if config_selected_param == 1 then
                    active_config_index = util.clamp(active_config_index + d, 1, #config_options)
                elseif config_selected_param == 2 then -- Change n.b voice
                    trackers[active_tracker_index].voice_index = util.clamp(trackers[active_tracker_index].voice_index + d, 1, #nb_voices)
                    params:set("voice_" .. active_tracker_index, trackers[active_tracker_index].voice_index)
                elseif config_selected_param == 3 then -- Change root octave
                    trackers[active_tracker_index].root_octave = util.clamp(trackers[active_tracker_index].root_octave + d, 1, 8)
                elseif config_selected_param == 4 then -- Change root visualized on grid
                    octave_on_grid = util.clamp(octave_on_grid + d, -1, 1)
                end
            end
        ----------
        -- Step --
        ----------
        elseif active_config_index == 3 then
            if n == 2 then
                config_selected_param = util.clamp(config_selected_param + d, 1, #param_names_table[3]) -- Parameters: Step, Velocity, Swing, Division, Duration
            elseif n == 3 then -- E3 to modify the selected parameter
                local step = trackers[active_tracker_index].phases[active_phase_index].steps[selected_step]
               
                if config_selected_param == 1 then
                    active_config_index = util.clamp(active_config_index + d, 1, #config_options)
                elseif config_selected_param == 2 then -- Navigate between steps
                    selected_step = util.clamp(selected_step + d, 1, trackers[active_tracker_index].phases[active_phase_index].length)
                elseif config_selected_param == 3 then -- Modify velocity
                    step.velocity = util.clamp(step.velocity + d*0.01, 0, 1) -- Increment by 0.01 for finer control
                elseif config_selected_param == 4 then -- Modify swing
                    step.swing = util.clamp(step.swing + d, 0, 100)
                elseif config_selected_param == 5 then -- Modify division
                    local current_division_index = index_of(division_options, step.division)
                    local new_division_index = util.clamp(current_division_index + d, 1, #division_options)
                    step.division = division_options[new_division_index]
                elseif config_selected_param == 6 then -- Modify duration
                    local current_duration_index = index_of(division_options, step.duration)
                    local new_duration_index = util.clamp(current_duration_index + d, 1, #division_options)
                    step.duration = division_options[new_duration_index]
                end
            end
        end
    end

    -------------------------------------
    -- Keyboard Config | Encoder Logic --
    -------------------------------------
    if app_mode_index == 3 then
        if n == 2 then
            config_selected_param = util.clamp(config_selected_param + d, 1, #keyboard_param_names[1])
        elseif n == 3 then
            if config_selected_param == 1 then
                keyboard_voice_index = util.clamp(keyboard_voice_index + d, 1, #nb_voices)
                params:set("keyboard_voice" , keyboard_voice_index)
            elseif config_selected_param == 2 then
                keyboard_root_octave = util.clamp(keyboard_root_octave + d, 0, 8)
            elseif config_selected_param == 3 then
                keyboard_string_distance = util.clamp(keyboard_string_distance + d, 1, 8)
            elseif config_selected_param == 4 then
                velocity_root = util.clamp(velocity_root + (d * 0.05), 0, 0.6)
            end
        end
    end

    redraw()
    grid_redraw()
end

-- Creating UI
function draw_settings()
    local is_active_pane = (active_ui_pane == 1)

    if app_mode_index == 1 then
        local param_names = global_param_names[1]
        local param_values = get_global_config_values()[1]

        local list_end = math.min(#param_names, scroll_index + max_items_on_screen - 1)

        for i = scroll_index, list_end do
            local y = 10 + (i - scroll_index) * 10 -- Adjust y position based on scroll_index
            if not is_active_pane then
                screen.level(2)
            else
                screen.level(i == config_selected_param and 15 or 5) -- Highlight the active parameter
            end
            screen.move(2, y)
            screen.text(param_names[i - scroll_index + 1] .. ": " .. param_values[i - scroll_index + 1])
        end   
    elseif app_mode_index == 2 then
        local param_names = param_names_table[active_config_index]
        local param_values = get_param_values_table()[active_config_index]

        local list_end = math.min(#param_names, scroll_index + max_items_on_screen - 1)

        for i = scroll_index, list_end do
            local y = 10 + (i - scroll_index) * 10 -- Adjust y position based on scroll_index
            if not is_active_pane then
                screen.level(2)
            else
                screen.level(i == config_selected_param and 15 or 5) -- Highlight the active parameter
            end
            screen.move(2, y)
            screen.text(param_names[i - scroll_index + 1] .. ": " .. param_values[i - scroll_index + 1])
        end
    elseif app_mode_index == 3 then
        local param_names = keyboard_param_names[1]
        local param_values = get_keyboard_config_values()

        local list_end = math.min(#param_names, scroll_index + max_items_on_screen - 1)

        for i = scroll_index, list_end do
            local y = 10 + (i - scroll_index) * 10 -- Adjust y position based on scroll_index
            if not is_active_pane then
                screen.level(2)
            else
                screen.level(i == config_selected_param and 15 or 5) -- Highlight the active parameter
            end
            screen.move(2, y)
            -- TODO: Something about this is wrong. I shouldn't be setting paramvalues[1][n] and should instead be setting an active_config_index
            screen.text(param_names[i - scroll_index + 1] .. ": " .. param_values[1][i - scroll_index + 1])
        end
    end
end

function draw_navigation()
    local is_active_pane = (active_ui_pane == 2)

    screen.level(8)
    screen.rect(84, 0, 44, 64)
    screen.fill()
    
    if app_mode_index == 1 then
        screen.font_size(8)
        screen.level(6)
        screen.move(105, 40)
        screen.text_center("k3")
        screen.level(0)
        screen.move(92, 60)
        screen.text("GLOBAL")
    elseif app_mode_index == 2 then
        -- Section Settings
        screen.font_face(1)

        -- Number
        screen.level(0)
        screen.font_size(14)
        screen.move(103, 12)
        screen.text_center(active_tracker_index)

        -- Title
        screen.level(2)
        screen.font_size(8)
        screen.move(105, 20)
        screen.text_center("wave")


        -- Section
        screen.level(0)
        screen.font_size(14)
        screen.move(103, 36)
        screen.text_center(active_phase_index)

        screen.level(2)
        screen.font_size(8)
        screen.move(105, 44)
        screen.text_center("phase")

        screen.level(0)
        screen.move(92, 60)
        screen.text("TRACKER")
    elseif app_mode_index == 3 then
        screen.font_size(8)
        screen.level(6)
        screen.move(105, 40)
        screen.text_center("k3")
        screen.level(0)
        screen.move(106, 60)
        screen.text_center("KEYBOARD")
    end

    screen.level(0)
    screen.rect(85, 50, 41, 1)
    screen.fill()

    screen.update()
end 

function redraw()
    screen.clear()
    draw_settings()
    draw_navigation()
end

function draw_tracker_canvas(working_tracker, working_phase)
    -- Define the adjusted degree range currently on grid
    local adjusted_degree_start = ((octave_on_grid + 1) * 7) + 1
    local adjusted_degree_end = adjusted_degree_start + 6

    -- Draw Tracker
    -- NB: Removed logic for scrolling window. May return it later.
    -- -- for step = active_window_start, active_window_start + 11 do -- Iterate through 12 steps starting at the active_window_start (determined by e1)
    -- -- local grid_step = step - active_window_start + 1 -- Adjusted step index so regardless of what actual numbered step we're talking about we're drawing on the visible window
    for step = 1, 12 do -- Iterate through 12 steps starting at the active_window_start (determined by e1)
        if step > max_steps then print("step exceeds length") break end -- Catch errors
        local grid_step = step

        -- Highlight step
        if step == working_tracker.current_position then
            for y = 1, 7 do -- Grid height for degrees
                g:led(grid_step, y, dim_light)
            end
        end
                
        for _, active_degree in ipairs(working_phase.steps[step].degrees or {}) do -- Grab the table of active degrees for this step    
            if is_in_range(active_degree, adjusted_degree_start, adjusted_degree_end) then -- Check if the degree's in the visible range based on octave_on_grid
                local mapped_degree = (active_degree - 1) % 7 + 1 -- Map the degree from its current value to 1 > 8 so it can be shon on the grid
                local mapped_grid_y = 8 - mapped_degree

                if step == working_tracker.current_position and active_phase_index == trackers[active_tracker_index].current_phase then -- Check if it's in the current step
                    g:led(grid_step, mapped_grid_y, max_light) -- If it is mark it with the highest brightness
                elseif step <= working_phase.length then -- N.B | This is holdover logic from the scrolling step window. Keeping it in case I want to return that feature
                    g:led(grid_step, mapped_grid_y, medium_light)
                else
                    g:led(grid_step, mapped_grid_y, dim_light)
                end
            else -- Otherwise mark it as active but out of range
                local mapped_degree = (active_degree - 1) % 7 + 1 -- Map the degree from its current value to 1 > 8 so it can be shon on the grid
                local mapped_grid_y = 8 - mapped_degree

                if step == working_tracker.current_position then -- Check if it's in the current step
                    g:led(grid_step, mapped_grid_y, medium_light) -- Mark it with the highest brightness
                elseif step <= working_phase.length then
                    g:led(grid_step, mapped_grid_y, dim_light)
                else
                    g:led(grid_step, mapped_grid_y, dim_light)
                end
            end
        end
    end
end

function draw_tracker_controls(working_tracker, working_phase)
    -- Highlight the 12 steps in the active window  length of the active tracker
    for y = MINIMAP_START_ROW, MINIMAP_END_ROW do
        for x = CONTROL_COLUMNS_START, CONTROL_COLUMNS_END do
            local lengthValue = ((y - MINIMAP_START_ROW) * 4) + (x - CONTROL_COLUMNS_START + 1)
            if lengthValue <= working_phase.length then
                -- Check if the current minimap position corresponds to the active step
                if lengthValue == working_tracker.current_position and active_phase_index == trackers[active_tracker_index].current_phase then
                    g:led(x, y, medium_light) -- Use high_light for the active step
                else
                    g:led(x, y, dim_light) -- Use a lower intensity for other steps
                end
            else
                g:led(x, y, 1)
            end
        end
    end

    -- Highlight the active tracker and phase on the control panel
    for x = CONTROL_COLUMNS_START, CONTROL_COLUMNS_END do
        local tracker_index = x - CONTROL_COLUMNS_START + 1

        if tracker_index == active_tracker_index then
            g:led(x, TRACKER_SELECTION_ROW, max_light) -- Light the active tracker at max_light intensity
        else
            g:led(x, TRACKER_SELECTION_ROW, 0) -- Other trackers remain at inactive_light intensity
        end


    end

    -- Display playback status for each tracker
    for i = 1, #trackers do
        -- Active playing illumination
        local playback_light = trackers[i].playing and medium_light or 0
        g:led(CONTROL_COLUMNS_START + i - 1, PLAYBACK_STATUS_ROW, playback_light)

        -- Soft light all phase rows
        g:led(CONTROL_COLUMNS_START + i - 1, TRACKER_FALLING_ROW, dim_light)
        g:led(CONTROL_COLUMNS_START + i - 1, TRACKER_RISING_ROW, dim_light)
        
        -- Active phase illumination
        if trackers[i].playing then
            if trackers[i].current_phase == 0 then
            elseif trackers[i].current_phase == 1 then
                g:led(CONTROL_COLUMNS_START + i - 1, TRACKER_RISING_ROW, medium_light)
            elseif trackers[i].current_phase == 2 then
                g:led(CONTROL_COLUMNS_START + i - 1, TRACKER_FALLING_ROW, medium_light)
            end

            -- Overwrite brightness for the active phase in the active tracker
            -- g:led(CONTROL_COLUMNS_START + i -1, active_phase_index, max_lights)
        end

        if i == active_tracker_index then
            g:led(CONTROL_COLUMNS_START + i - 1, 7 - active_phase_index, max_light)
        end
    end

    -- Octave control keys lighting logic
    local octave_keys = {-1, 0, 1} -- Matches the possible values of octave_on_grid
    for i, octave_key in ipairs(octave_keys) do
        if octave_on_grid == octave_key then
            g:led(i, 8, medium_light) -- Active key with medium_light
        else
            g:led(i, 8, dim_light) -- Inactive keys with dim_light
        end
    end
end

-- Creating Grid
-- TODO: Need to totally refactor this so that it does a first pass drawing the UI and a second pass drawing the state
function grid_redraw()
    if not g then
        print("no grid found")
        return
    end

    g:all(0) -- Zero out grid

    if app_mode_index == 1 then
    elseif app_mode_index == 2 then
        local working_tracker = trackers[active_tracker_index]    
        local working_phase = working_tracker.phases[active_phase_index]
    
        draw_tracker_canvas(working_tracker, working_phase)
        draw_tracker_controls(working_tracker, working_phase)
    elseif app_mode_index == 3 then
        draw_clonky()
    end

    g:refresh() -- Send the LED buffer to the grid
end

---------------------------
-- Some helper functions --
---------------------------
function create_scale_names_table()
    for i = 1, #musicutil.SCALES do
        table.insert(scale_names, musicutil.SCALES[i].name) 
    end
end

function index_of(tbl, value) -- Find the index of an item in a table
    for i, v in ipairs(tbl) do
        if v == value then
            return i
        end
    end
    return nil
end

function is_in_range(value, min, max) -- Check to see if a value is within a range
    return value >= min and value <= max
end

------------------
-- Start Script --
------------------
-- TODO: This kickoff is really awkward
function init()
    -- Creaters trackers and adds them to global table
    trackers = {  
        create_tracker(nil, 4),
        create_tracker(nil, 4),
        create_tracker(nil, 4),
        create_tracker(nil, 4)
    }
    
    create_scale_names_table()
    -- Creates lattice sequencers that reference trackers
    create_sequencers()
    
    -- Sets up menus
    params:add_separator("dawn_title", "Dawn")
    params:add_separator("voices", "N.B Voices")

    -- N.B Setup
    nb:init()
    -- Adds voice option to trackers
    for i = 1, #trackers do
        nb:add_param("voice_" .. i, "voice_" .. i)
    end

    nb:add_param("keyboard_voice", "keyboard_voice")

    nb:add_player_params()

    local voice_lookup = params:lookup_param("voice_1")

    for i, option in ipairs(voice_lookup.options) do
        nb_voices[i] = option
    end

    -- Start
    primary_lattice:start()
    redraw()
    grid_redraw()
end
