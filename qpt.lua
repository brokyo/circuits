-- TBD
-- Quad polyphonic tracker
-- A work in progess

-- -- Core libraries
local nb = require "nb/lib/nb"
local musicutil = require "musicutil"
local lattice = require "lattice"

local scale_names = {} -- Table to hold scale names so they're usable in the setting params
for i = 1, #musicutil.SCALES do
    table.insert(scale_names, musicutil.SCALES[i].name) 
end

local g = grid.connect()

---------------------------
-- Some helper functions --
---------------------------
function index_of(tbl, value) 
    for i, v in ipairs(tbl) do
        if v == value then
            return i
        end
    end
    return nil
end

function is_in_range(value, min, max)
    return value >= min and value <= max
end

function map_int(value, min, max)
    return math.floor(math.min(math.max(value, min), max) + 0.5)
end
-- Grid lighting configuration
local inactive_light = 2
local dim_light = 3
local medium_light = 6
local high_light = 10

-- UI variables
local active_tracker_index = 1 -- Manage editable state on screen and grid
local active_window_start = 1 -- Manage the editable window on the grid 

local active_section = "loop" -- Vairable to identify and control the active section of the screen
local selected_step = 1 -- Individual step to edit
local loop_selected_param = 1 -- Index to navigate between parameters in the loop section
local step_selected_param = 1 -- Index to navigate between parameters in the step section

local division_options = {1/16, 1/8, 1/4, 1/3, 1/2, 2/3, 1, 2, 4} -- Possible step divisions
local division_option_names = {"1/16", "1/8", "1/4", "1/3", "1/2", "2/3", "1", "2", "4", "8"} -- Names as strings for showing in param list

local octave_on_grid = 0 -- Index to allow octave selection on the grid

-- Constants to separate the control panel
local CONTROL_COLUMNS_START = 13
local CONTROL_COLUMNS_END = 16
local MINIMAP_START_ROW = 1
local MINIMAP_END_ROW = 6
local PLAYBACK_STATUS_ROW = 7
local TRACKER_SELECTION_ROW = 8

-- Table for catching keycombos
local key_states = {
    tracker_selection = {},
    minimap = {}
}

function create_tracker(voice_id, active_length, root_octave) -- Helper function to make multiple trackers
    local MAX_STEPS = 24 
    local tracker = {
        voice_id = voice_id,
        playing = false,
        current_position = 0,
        length = active_length,  -- Number of steps (of MAX_STEPS) to be played 
        steps = {},
        root_octave = root_octave
    }
    
    -- Initialize steps with default values
    for i = 1, MAX_STEPS do
        table.insert(tracker.steps, {degrees = {}, velocity = 0.5, swing = 50, division = 1/4, duration = 1/4})
    end
    
    return tracker
end

local trackers = {
    create_tracker(nil, 8, 4),
    create_tracker(nil, 12, 4),
    create_tracker(nil, 16, 4),
    create_tracker(nil, 24, 4)
}

function build_scale(root_octave) -- Helper function for building scales from root note and mode set in settings
    local root_note = ((root_octave - 1) * 12) + params:get("key") - 1 -- Get the MIDI note for one octave below the root. Adjust by 1 due to Lua indexing
    local scale = musicutil.generate_scale(root_note, params:get("mode"), 3)
 
    return scale
end

primary_lattice = lattice:new()

local sequencers = {}
for i = 1, #trackers do
    local tracker = trackers[i] -- Create an alias for convenience
    tracker.voice_id = i -- Assign an id to the tracker voice so we can manage it with n.b elsewhere
    
    sequencers[i] = primary_lattice:new_sprocket{
        action = function()
            if tracker.playing then -- Check if the tracker is playing
                tracker.current_position = (tracker.current_position % tracker.length) + 1 -- Increase the tracker position (step) at the end of the call. Loop through if it croses the length.

                local current_step = tracker.steps[tracker.current_position] -- Get the table at the current step to configure play event

                local degree_table = tracker.steps[tracker.current_position].degrees -- Get the table of degrees to play for this step
                local scale_notes = build_scale(tracker.root_octave) -- Generate a scale based on global key and mode
                
                sequencers[i]:set_division(current_step.division) -- Set the division for the current step
                sequencers[i]:set_swing(current_step.swing) -- Set the swing for the current step

                if #degree_table > 0 then -- Check to see if the degree table at the current step contains values
                    for _, degree in ipairs(degree_table) do  -- If it does is, iterate through each degree
                        local note = scale_notes[degree] -- And match it to the appropriate note in the scale
                        local player = params:lookup_param("voice_" .. i):get_player() -- Get the n.b voice
                        player:play_note(note, current_step.velocity, current_step.duration) -- And play the note
                    end
                end
                grid_redraw()
            end
        end,
        division = 1
    }
end

-- Logic for changing the active tracker
function change_active_tracker(trackerIndex)
    active_tracker_index = trackerIndex
    octave_on_grid = 0 -- Reset the grid to the new tracker's root
    grid_redraw()
    redraw()
end

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

function step_edit_shortcut(tracker_index, minimap_key)
    if minimap_key == nil then return end -- Exit function if there's no minimap_key pressed
    active_section = "step"
    active_tracker_index = tracker_index
    selected_step = minimap_key
    redraw()
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


function key(n, z)
    if n == 2 and z == 1 then -- K2 switches to Loop section
        active_section = "loop"
        redraw()
    elseif n == 3 and z == 1 then -- K3 switches to Step section 
        active_section = "step"
        redraw()
    end
end


function enc(n, d)
    if n == 1 then -- Encoder 1 adjusts the active window start in all modes
        active_window_start = util.clamp(active_window_start + d, 1, 13) -- Ensures the window doesn't go beyond the steps. Adjusts up to step 13 to allow a full window of 12 steps.
        grid_redraw()
    elseif active_section == "loop" then
        if n == 2 then -- E2 navigates between parameters in the Loop section
            loop_selected_param = util.clamp(loop_selected_param + d, 1, 2) -- Two parameters: Root Octave, Octave On Grid
            redraw()
        elseif n == 3 then -- E3 modifies the selected parameter
            if loop_selected_param == 1 then -- Change root octave
                trackers[active_tracker_index].root_octave = util.clamp(trackers[active_tracker_index].root_octave + d, 1, 8)
                redraw()
            elseif loop_selected_param == 2 then -- Change loop length
                octave_on_grid = util.clamp(octave_on_grid + d, -1, 1)
                grid_redraw()
                redraw()
            end
        end
    elseif active_section == "step" then
        if n == 2 then -- E2 to select parameter to edit
            step_selected_param = util.clamp(step_selected_param + d, 1, 5)
            redraw()
        elseif n == 3 then -- E3 to modify the selected parameter
            local step = trackers[active_tracker_index].steps[selected_step]
            if step_selected_param == 1 then -- Navigate between steps
                selected_step = util.clamp(selected_step + d, 1, #trackers[active_tracker_index].steps)
            elseif step_selected_param == 2 then -- Modify velocity
                step.velocity = util.clamp(step.velocity + d*0.01, 0, 1) -- Increment by 0.01 for finer control
            elseif step_selected_param == 3 then -- Modify swing
                step.swing = util.clamp(step.swing + d, 0, 100)
            elseif step_selected_param == 4 then -- Modify division
                local current_division_index = index_of(division_options, step.division)
                local new_division_index = util.clamp(current_division_index + d, 1, #division_options)
                step.division = division_options[new_division_index]
            elseif step_selected_param == 5 then -- Modify duration
                local current_duration_index = index_of(division_options, step.duration)
                local new_duration_index = util.clamp(current_duration_index + d, 1, #division_options)
                step.duration = division_options[new_duration_index]
            end
            redraw()
        end
    end
end

function redraw()
    screen.clear()

    -- Mode Selector
    -- Loop Edit
    screen.rect(1, 54, 60, 10)    
    if active_section == "loop" then
        screen.level(6)
    else
        screen.level(1)
    end
    screen.stroke()
    screen.move(32, 61)
    screen.text_center("Loop (k2)")

    -- Step Edit
    screen.rect(67, 54, 60, 10)
    if active_section == "step" then
        screen.level(6)
    else
        screen.level(1)
    end
    screen.stroke()
    screen.move(96, 61)
    screen.text_center("Step (k3)")

    if active_section == "loop" then
        local param_names = {"Octave", "Octave on Grid"}
        local octave_on_grid_display = "root"

        -- Check the octave_on_grid int and show a string in the UI 
        if octave_on_grid == -1 then
            octave_on_grid_display = "root - 1"
        elseif octave_on_grid == 1 then
            octave_on_grid_display = "root + 1"
        else
            local octave_on_grid_display = "root"
        end

        local param_values = {
            tostring(trackers[active_tracker_index].root_octave),
            octave_on_grid_display
        }
        
        for i, param in ipairs(param_names) do
            screen.level(i == loop_selected_param and 15 or 5) -- Highlight the active parameter
            screen.move(2, 10 + (i * 10))
            screen.text(param .. ": " .. param_values[i])
        end
    elseif active_section == "step" then
        -- Draw parameters for the selected step
        local step = trackers[active_tracker_index].steps[selected_step]
        local param_names = {"Step", "Velocity", "Swing", "Division", "Duration (steps)"}
        local param_values = {tostring(selected_step), tostring(step.velocity), tostring(step.swing), division_option_names[index_of(division_options, step.division)], division_option_names[index_of(division_options, step.duration)]}

        for i, param in ipairs(param_names) do
            screen.level(i == step_selected_param and 15 or 5) -- Highlight the active parameter
            screen.move(2, 0 + (i * 10))
            screen.text(param .. ": " .. param_values[i])
        end
    end
    screen.update()
end

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
                else 
                    g:led(grid_step, mapped_grid_y, medium_light)
                end
            else -- Otherwise mark it as active but out of range
                local mapped_degree = (active_degree - 1) % 7 + 1 -- Map the degree from its current value to 1 > 8 so it can be shon on the grid
                local mapped_grid_y = 8 - mapped_degree

                if step == working_tracker.current_position then -- Check if it's in the current step
                    g:led(grid_step, mapped_grid_y, medium_light) -- Mark it with the highest brightness
                else
                    g:led(grid_step, mapped_grid_y, dim_light)
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

function init()
    
    params:add{
        type = "option",
        id = "key",
        name = "Key",
        options = musicutil.NOTE_NAMES,
        default = 3
      }
      
      params:add{
        type = "option",
        id = "mode",
        name = "Mode",
        options = scale_names,
        default = 5,
      }

    nb:init()
    for i = 1, #trackers do
        nb:add_param("voice_" .. i, "voice_" .. i)
    end
    nb:add_player_params()

    primary_lattice:start()
    grid_redraw()

end
