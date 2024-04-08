-- Dawn/Dusk
-- Two phase polyphonic trackers
-- with per-step timing configuration
-- Rows are in-scale notes
-- Columns are steps
-- Supports n.b voices
-- 
-- |Quickstart|
-- Grid to program trackers
-- Lower left sets octave
-- Lower right selects active tracker
-- Row above controls playback
-- E1 scrolls through all steps
--
-- |UI|
-- K2,K3 active section of UI
-- E2 scrolls list, E3 changes values
-- 
-- |Step Editing Key Combo|
-- Hold tracker button and press step to jump
-- to that step's edit page

--------------------
-- Core libraries --
--------------------
local nb = require "nb/lib/nb"
local musicutil = require "musicutil"
local lattice = require "lattice"
local g = grid.connect()

--------------------
-- Configuration  --
--------------------
-- Timbre
local scale_names = {} -- Table to hold scale names so they can be listed as strings
local scale_index = 1
local tonic_index = 3

-- UI 
-- UI > Index for nav/data
local active_ui_pane = 2
local active_tracker_index = 1 -- Manage editable state on screen and grid
local active_window_start = 1 -- Manage the editable window on the grid 
local active_config_index = 1 -- Manage the config view & retrieve relevant data
local config_selected_param = 1 -- Track selected parameter for setting screen.light
local selected_step = 1 -- Individual step to edit

-- UI > Navigation View
local navigation_selected_param = 1
local navigation_parms_names = {
    "wave",
    "config"
}
local navigation_params_values = {
    active_tracker_index,
    active_config_index
}

-- UI > Config View
local param_names_table = {
    -- Global
    {
        "Mode",
        "Key",
        "Tempo"
    },
    -- Wave
    {
        "Clock Mod"
        -- "Phasing Active",
        -- "Rising Start Step",
        -- "Rising Stop Step"
        -- "Rising Cycles",
        -- "Falling Start Step",
        -- "Falling Stop Step",
        -- "Falling Cycles"
    },
    -- Loop
    {
        "Voice",
        "Octave",
        "Grid Oct Shift",
    },
    -- Step
    {
        "Step", 
        "Velocity", 
        "Swing", 
        "Division", 
        "Beats Sus"
    }
}

-- UI > Naming maps
local config_options = {"Global", "Wave", "Voice", "Step"} -- Naming config pages for UI
local division_options = {1/16, 1/8, 1/4, 1/3, 1/2, 2/3, 1, 2, 4, 8} -- Possible step divisions
local division_option_names = {"1/16", "1/8", "1/4", "1/3", "1/2", "2/3", "1", "2", "4", "8"} -- Names as strings for showing in param list
local clock_modifider_options = {8, 4, 2, 1, 1/2, 1/4, 1/8} -- Multiplied to duration selection to set wave-wide clock modifications
local clock_modifider_options_names = {"/8", "/4", "/2", "x1", "x2", "x4", "x8"}
local octave_on_grid = 0 -- the octave that appears on the grid

-- UI > Scrolling Controls
local scroll_index = 1 -- Track the first visible item in a long list
local max_items_on_screen = 6 

-- Grid
-- Grid > lighting 
local inactive_light = 2
local dim_light = 5
local medium_light = 12
local high_light = 15

-- Grid > control panel locations
local CONTROL_COLUMNS_START = 13
local CONTROL_COLUMNS_END = 16
local MINIMAP_START_ROW = 1
local MINIMAP_END_ROW = 6
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

function create_tracker(voice_id, active_length, root_octave) -- Create trackers and set defaults
    local MAX_STEPS = 24 
    local tracker = {
        voice_id = voice_id,
        voice_index = 1,
        playing = false,
        current_position = 0,
        length = active_length,  -- Number of steps (of MAX_STEPS) to be played 
        steps = {},
        loop_count = 0,
        root_octave = root_octave,
        clock_modifider = 1,
        phase_active = false,
        rising = {
            start = 1,
            stop = 24,
            cycles = 1
        },
        rising = {
            start = 1,
            stop = 24,
            cycles = 1
        }
    }
    
    -- Initialize steps with default values
    for i = 1, MAX_STEPS do
        table.insert(tracker.steps, {degrees = {}, velocity = 0.9, swing = 50, division = 1/4, duration = 1})
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
                    -- TODO: This works, but I've got both current_position and loop_count zero-indexed and I worry there will be reprecussions. Revisit this.
                    tracker.current_position = (tracker.current_position % tracker.length) + 1 -- Increase the tracker position (step) at the end of the call. Loop through if it croses the length.
                    if tracker.current_position == 1 then
                        tracker.loop_count = tracker.loop_count + 1
                    end
                    
                    local current_step = tracker.steps[tracker.current_position] -- Get the table at the current step to configure play event
                    
                    local degree_table = tracker.steps[tracker.current_position].degrees -- Get the table of degrees to play for this step
                    local scale_notes = build_scale(tracker.root_octave) -- Generate a scale based on global key and mode

                    local modified_division = tracker.clock_modifider * current_step.duration
                
                    sequencers[i]:set_division(modified_division) -- Set the division for the current step
                    sequencers[i]:set_swing(current_step.swing) -- Set the swing for the current step

                    if #degree_table > 0 then -- Check to see if the degree table at the current step contains values
                        for _, degree in ipairs(degree_table) do  -- If it does is, iterate through each degree
                            local note = scale_notes[degree] -- And match it to the appropriate note in the scale
                            local player = params:lookup_param("voice_" .. i):get_player() -- Get the n.b voice
                            player:play_note(note, current_step.velocity, modified_division) -- And play the note
                        end
                    end
                    grid_redraw()
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
    local anyTrackerSelectionKeyPressed = false
    for _, isPressed in pairs(key_states.tracker_selection) do
        if isPressed then
            anyTrackerSelectionKeyPressed = true
            break
        end
    end

    -- Only update tracker length if no tracker selection key is pressed
    if not anyTrackerSelectionKeyPressed then
        local lengthOffset = ((y - MINIMAP_START_ROW) * 4) + (x - CONTROL_COLUMNS_START + 1)
        trackers[active_tracker_index].length = lengthOffset
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

-- Logic to change playback state
function toggle_tracker_playback(tracker_index)
    local tracker_to_change = trackers[tracker_index]
    tracker_to_change.playing = not tracker_to_change.playing -- Flip the playback status
    -- And reset position to zero if we're stopping
    if not tracker_to_change.playing then
        tracker_to_change.current_position = 0
    end
    redraw()
    grid_redraw()
end

-- Logic for handling key pressed on the control panel (columns 13 > 16)
function handle_control_column_press(x, y, pressed)
    -- Update key_states table
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

function g.key(x, y, pressed)    
    if x >= CONTROL_COLUMNS_START and x <= CONTROL_COLUMNS_END then
        handle_control_column_press(x, y, pressed)
    elseif y == 8 then
        hanlde_octave_change(x, y, pressed)
    else
        local working_tracker = trackers[active_tracker_index]
        local adjusted_x = x + active_window_start - 1

        -- Invert y-coordinate to match the horizontal layout and adjust for octave_on_grid
        local degree = ((octave_on_grid + 1) * 7) + (8 - y) -- Inverting y by using (9 - y)

        if pressed == 1 and adjusted_x <= 21 then
            local index = nil
            for i, v in ipairs(working_tracker.steps[adjusted_x].degrees) do
                if v == degree then
                    index = i
                    break
                end
            end
            if index then
                table.remove(working_tracker.steps[adjusted_x].degrees, index)
                print("Degree " .. degree .. " removed from step " .. adjusted_x)
            else
                table.insert(working_tracker.steps[adjusted_x].degrees, degree)
                print("Degree " .. degree .. " added to step " .. adjusted_x)
            end
            grid_redraw()
        end
    end
end

------------------
-- UI Functions --
------------------
-- Logic for changing the active tracker
function change_active_tracker(new_tracker_index)
    active_tracker_index = new_tracker_index
    octave_on_grid = 0 -- Reset the grid to the new tracker's root
    grid_redraw()
    redraw()
end

function change_active_config(new_config_index)
    active_config_index = new_config_index
    grid_redraw()
    redraw()
end

function get_param_values_table() -- Returns a refresehed table of all param values
    return {
        {
            tostring(scale_names[scale_index]),
            tostring(musicutil.NOTE_NAMES[tonic_index]),
            tostring(params:get('clock_tempo')),
        },
        {
            clock_modifider_options_names[index_of(clock_modifider_options, trackers[active_tracker_index].clock_modifider)]
        },
        {
            tostring(nb_voices[trackers[active_tracker_index].voice_index]),
            tostring(trackers[active_tracker_index].root_octave),
            tostring(octave_on_grid),
        },
        {
            tostring(selected_step), 
            tostring(trackers[active_tracker_index].steps[selected_step].velocity), 
            tostring(trackers[active_tracker_index].steps[selected_step].swing), 
            division_option_names[index_of(division_options, trackers[active_tracker_index].steps[selected_step].division)], 
            division_option_names[index_of(division_options, trackers[active_tracker_index].steps[selected_step].duration)]
        }
    }
end


-- Physical Controls
function key(n, z)
    if n == 2 and z == 1 then -- K2 switches to config pane
        active_ui_pane = 1
        redraw()
    elseif n == 3 and z == 1 then -- K3 switches to Nav pane 
        active_ui_pane = 2
        redraw()
    end
end

function enc(n, d)
    -- Encoder 1 adjusts the active window start in all modes
    if n == 1 then 
        active_window_start = util.clamp(active_window_start + d, 1, 13) -- Ensures the window doesn't go beyond the steps. Adjusts up to step 13 to allow a full window of 12 steps.
        grid_redraw()
    end

    ---------------------------------
    -- Config Pane | Encoder Logic --
    ---------------------------------
    if active_ui_pane == 1 then
        ------------
        -- Global --
        ------------
        if active_config_index == 1 then
            if n == 2 then
                config_selected_param = util.clamp(config_selected_param + d, 1, #param_names_table[1]) -- Parameters: Mode, Key, Tempo, Section
            elseif n == 3 then
                if config_selected_param == 1 then
                    scale_index = util.clamp(scale_index + d, 1, #scale_names)
                elseif config_selected_param == 2 then
                    tonic_index = util.clamp(tonic_index + d, 1, #musicutil.NOTE_NAMES)
                elseif config_selected_param == 3 then
                    params:delta("clock_tempo",d)
                end
            end
        ----------
        -- Wave --
        ----------
        elseif active_config_index == 2 then
            if n == 2 then
                config_selected_param = util.clamp(config_selected_param + d, 1, #param_names_table[2]) -- Parameters: Clock modifier 
            elseif n == 3 then
                if config_selected_param == 1 then
                    local current_mod_index = index_of(clock_modifider_options, trackers[active_tracker_index].clock_modifider)
                    local new_clock_mod_index = util.clamp(current_mod_index + d, 1, #clock_modifider_options)
                    trackers[active_tracker_index].clock_modifider = clock_modifider_options[new_clock_mod_index]           
                end
            end
        ----=------
        -- Voice --
        -----------
        elseif active_config_index == 3 then
            if n == 2 then 
                config_selected_param = util.clamp(config_selected_param + d, 1, #param_names_table[3]) -- Parameters: Voice, Root Octave, Octave On Grid
            elseif n == 3 then
                if config_selected_param == 1 then -- Change n.b voice
                    trackers[active_tracker_index].voice_index = util.clamp(trackers[active_tracker_index].voice_index + d, 1, #nb_voices)
                    params:set("voice_" .. active_tracker_index, trackers[active_tracker_index].voice_index)
                elseif config_selected_param == 2 then -- Change root octave
                    trackers[active_tracker_index].root_octave = util.clamp(trackers[active_tracker_index].root_octave + d, 1, 8)
                elseif config_selected_param == 3 then -- Change root visualized on grid
                    octave_on_grid = util.clamp(octave_on_grid + d, -1, 1)
                end
            end
        ----------
        -- Step --
        ----------
        elseif active_config_index == 4 then
            if n == 2 then
                config_selected_param = util.clamp(config_selected_param + d, 1, #param_names_table[4]) -- Parameters: Step, Velocity, Swing, Division, Duration
            elseif n == 3 then -- E3 to modify the selected parameter
                local step = trackers[active_tracker_index].steps[selected_step]
                if config_selected_param == 1 then -- Navigate between steps
                    selected_step = util.clamp(selected_step + d, 1, #trackers[active_tracker_index].steps)
                elseif config_selected_param == 2 then -- Modify velocity
                    step.velocity = util.clamp(step.velocity + d*0.01, 0, 1) -- Increment by 0.01 for finer control
                elseif config_selected_param == 3 then -- Modify swing
                    step.swing = util.clamp(step.swing + d, 0, 100)
                elseif config_selected_param == 4 then -- Modify division
                    local current_division_index = index_of(division_options, step.division)
                    local new_division_index = util.clamp(current_division_index + d, 1, #division_options)
                    step.division = division_options[new_division_index]
                elseif config_selected_param == 5 then -- Modify duration
                    local current_duration_index = index_of(division_options, step.duration)
                    local new_duration_index = util.clamp(current_duration_index + d, 1, #division_options)
                    step.duration = division_options[new_duration_index]
                end
            end
        end
    end

    -------------------------------------
    -- Navigation Pane | Encoder Logic --
    -------------------------------------
    if active_ui_pane == 2 then
        if n == 2 then
            navigation_selected_param = util.clamp(navigation_selected_param + d, 1, 2)
        elseif n == 3 then
            if navigation_selected_param == 1 then
                navigation_params_values[1] = util.clamp(navigation_params_values[1] + d, 1, #trackers)
                change_active_tracker(navigation_params_values[1])
            elseif navigation_selected_param == 2 then
                navigation_params_values[2] = util.clamp(navigation_params_values[2] + d, 1, #config_options)
                change_active_config(navigation_params_values[2])
            end
        end
    end

    redraw()
    grid_redraw()
end

-- Creating UI
function draw_settings()
    local is_active_pane = (active_ui_pane == 1)

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
end

function draw_navigation()
    local is_active_pane = (active_ui_pane == 2)

    screen.level(is_active_pane and 15 or 8)
    screen.rect(84, 0, 44, 64)
    screen.fill()
    
    -- Section Settings
    screen.font_face(1)

    -- Number
    if is_active_pane and navigation_selected_param == 1 then
        screen.level(0)
    elseif is_active_pane and navigation_selected_param ~= 1 then
        screen.level(2)
    elseif not is_active_pane then
        screen.level(0)
    end
    screen.font_size(16)
    screen.move(103, 15)
    if active_config_index == 1 then
        screen.text_center("all")
    else
        screen.text_center(active_tracker_index)
    end

    -- Title
    if is_active_pane and navigation_selected_param == 1 then
        screen.level(0)
    elseif is_active_pane and navigation_selected_param ~= 1 then
        screen.level(4)
    elseif not is_active_pane then
        screen.level(2)
    end
    screen.font_size(8)
    screen.move(105, 24)
    screen.text_center("wave")


    -- Section
    if is_active_pane and navigation_selected_param == 2 then
        screen.level(0)
    elseif is_active_pane and navigation_selected_param ~= 2 then
        screen.level(2)
    elseif not is_active_pane then
        screen.level(0)
    end
    screen.font_size(8)
    screen.move(105, 46)
    screen.text_center(config_options[active_config_index])

    -- Title
    if is_active_pane and navigation_selected_param == 2 then
        screen.level(0)
    elseif is_active_pane and navigation_selected_param ~= 2 then
        screen.level(4)
    elseif not is_active_pane then
        screen.level(2)
    end


    screen.font_size(8)
    screen.move(105, 56)
    screen.text_center("config")
    
    screen.update()
end 

function redraw()
    screen.clear()
    draw_settings()
    draw_navigation()
end

-- Creating Grid
function grid_redraw()
    if not g then
        print("no grid found")
        return
    end

    local working_tracker = trackers[active_tracker_index]    

    g:all(0) -- Zero out grid


    -- Define the adjusted degree range currently on grid
    local adjusted_degree_start = ((octave_on_grid + 1) * 7) + 1
    local adjusted_degree_end = adjusted_degree_start + 6

    -- Draw Tracker
    for step = active_window_start, active_window_start + 11 do -- Iterate through 12 steps starting at the active_window_start (determined by e1)
        if step > 24 then print("step exceeds length") break end -- Catch errors
        local grid_step = step - active_window_start + 1 -- Adjusted step index so regardless of what actual numbered step we're talking about we're drawing on the visible window

        if step == working_tracker.current_position then
            for y = 1, 7 do -- Grid height for degrees
                g:led(grid_step, y, dim_light)
            end
        end
                
        for _, active_degree in ipairs(working_tracker.steps[step].degrees or {}) do -- Grab the table of active degrees for this step    
            if is_in_range(active_degree, adjusted_degree_start, adjusted_degree_end) then -- Check if the degree's in the visible range based on octave_on_grid
                local mapped_degree = (active_degree - 1) % 7 + 1 -- Map the degree from its current value to 1 > 8 so it can be shon on the grid
                local mapped_grid_y = 8 - mapped_degree

                if step == working_tracker.current_position then -- Check if it's in the current step
                    g:led(grid_step, mapped_grid_y, high_light) -- If it is mark it with the highest brightness
                elseif step <= working_tracker.length then
                    g:led(grid_step, mapped_grid_y, medium_light)
                else
                    g:led(grid_step, mapped_grid_y, dim_light)
                end
            else -- Otherwise mark it as active but out of range
                local mapped_degree = (active_degree - 1) % 7 + 1 -- Map the degree from its current value to 1 > 8 so it can be shon on the grid
                local mapped_grid_y = 8 - mapped_degree

                if step == working_tracker.current_position then -- Check if it's in the current step
                    g:led(grid_step, mapped_grid_y, medium_light) -- Mark it with the highest brightness
                elseif step < working_tracker.length then
                    g:led(grid_step, mapped_grid_y, dim_light)
                else
                    g:led(grid_step, mapped_grid_y, 1)
                end
            end
        end

    -- Highlight the 12 steps in the active window  length of the active tracker
    for y = MINIMAP_START_ROW, MINIMAP_END_ROW do
        for x = CONTROL_COLUMNS_START, CONTROL_COLUMNS_END do
            local lengthValue = ((y - MINIMAP_START_ROW) * 4) + (x - CONTROL_COLUMNS_START + 1)
            if lengthValue <= trackers[active_tracker_index].length then
                -- Check if the current minimap position corresponds to the active step
                if lengthValue == working_tracker.current_position then
                    g:led(x, y, medium_light) -- Use high_light for the active step
                else
                    g:led(x, y, dim_light) -- Use a lower intensity for other steps
                end
            else
                g:led(x, y, 1)
            end
        end
    end

    -- Highlight the active tracker in the control panel
    for x = CONTROL_COLUMNS_START, CONTROL_COLUMNS_END do
        local trackerIndex = x - CONTROL_COLUMNS_START + 1
        if trackerIndex == active_tracker_index then
            g:led(x, TRACKER_SELECTION_ROW, medium_light) -- Light the active tracker at medium_light intensity
        else
            g:led(x, TRACKER_SELECTION_ROW, 0) -- Other trackers remain at inactive_light intensity
        end
    end

    -- Display playback status for each tracker on row 7
    for i = 1, #trackers do
        local playbackLight = trackers[i].playing and high_light or 0
        g:led(CONTROL_COLUMNS_START + i - 1, PLAYBACK_STATUS_ROW, playbackLight)
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

    g:refresh() -- Send the LED buffer to the grid
    end
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
function init()
    print(clock.get_beat_sec())
    -- TODO: This kickoff is really awkward
    -- Creaters trackers and adds them to global table
    trackers = {  
        create_tracker(nil, 8, 4),
        create_tracker(nil, 12, 4),
        create_tracker(nil, 16, 4),
        create_tracker(nil, 24, 4)
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
