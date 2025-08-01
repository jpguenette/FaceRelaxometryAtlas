function draw_and_analyze_roi(locations_path, slice_index)
    % Initialize shared state
    current_slice = slice_index;
    h_circle1 = [];
    h_circle2 = [];
    vol1 = [];
    vol2 = [];
    vol1_Hist = [];
    vol2_Hist = [];

    % Create UI
    fig = uifigure('Name', 'ROI Drawing Tool', 'Position', [100 100 1200 600]);
    gl = uigridlayout(fig, [4 2]);
    gl.RowHeight = {30, 30, '1x', 50}; 
    gl.ColumnWidth = {'1x', '1x'};

    % Subject dropdown label
    subject_label = uilabel(gl, 'Text', 'Subject:');
    subject_label.Layout.Row = 1;
    subject_label.Layout.Column = 1;

    % Get all SUBJECT folders
    folder_list = dir('SUBJECT*');
    subject_dirs = {folder_list([folder_list.isdir]).name};
    subject_names = ["--Select--", subject_dirs];

    locations = readlines(locations_path);
    locations_dropdown = ['--Select--', locations'];

    selected_subject_dir = '';
    
    % Dropdown menu
    subject_dropdown = uidropdown(gl, ...
        'Items', subject_names, ...
        'Value', "--Select--", ...
        'ValueChangedFcn', @(dd,event)load_subject(dd.Value));
    subject_dropdown.Layout.Row = 2;
    subject_dropdown.Layout.Column = 1;

    % Body part name input
    location_label = uilabel(gl, 'Text', 'Location:');
    location_label.Layout.Row = 1;
    location_label.Layout.Column = 2;

    % Dropdown menu
    location_input = uidropdown(gl, ...
        'Items', locations_dropdown, ...
        'Value', "--Select--");
    location_input.Layout.Row = 2;
    location_input.Layout.Column = 2;

    % Axes for images
    ax1 = uiaxes(gl);
    ax1.Layout.Row = 3;
    ax1.Layout.Column = 1;
    
    ax2 = uiaxes(gl);
    ax2.Layout.Row = 3;
    ax2.Layout.Column = 2;

    % Submit button
    btn = uibutton(gl, 'Text', 'Submit', 'ButtonPushedFcn', @(btn,event)submit_callback());
    btn.Layout.Row = 4;
    btn.Layout.Column = 2;

    % Draw ROI button
    draw_btn = uibutton(gl, 'Text', 'Draw ROI', 'ButtonPushedFcn', @(btn,event)draw_roi());
    draw_btn.Layout.Row = 4;
    draw_btn.Layout.Column = 1;

    % Initial blank images
    update_displayed_slices();

    % Scroll callback
    fig.WindowScrollWheelFcn = @scroll_callback;

    fig.KeyPressFcn = @key_callback;

    % ----------------- Callback: Load Subject -----------------
    function load_subject(subject_name)
        if subject_name == "--Select--"
            vol1 = [];
            vol2 = [];
            vol1_Hist = [];
            vol2_Hist = [];
            update_displayed_slices();
            selected_subject_dir = subject_name;
            return;
        end
        selected_subject_dir = subject_name;
        file1 = fullfile(subject_name, 'QUANT_MAPS', 'T1_epi.mat');
        file2 = fullfile(subject_name, 'QUANT_MAPS', 'T2_epi.mat');

        if exist(file1, 'file') && exist(file2, 'file')
            data1 = load(file1);
            data2 = load(file2);
            fields1 = fieldnames(data1);
            fields2 = fieldnames(data2);
            vol1 = data1.(fields1{1});
            vol2 = data2.(fields2{1});
            
            % Validate
            if ~isequal(size(vol1), size(vol2))
                uialert(fig, 'T1 and T2 image volumes are not the same size.', 'Data Error');
                return;
            end
            
            % Clean
            vol1_Hist = apply_nan_thresholds(vol1, 100, 2500);
            vol2_Hist = apply_nan_thresholds(vol2, 10, 300);

            % Update slice view
            update_displayed_slices();
        else
            uialert(fig, 'T1 or T2 .mat file not found.', 'File Error');
        end
    end

    % ----------------- Scroll Callback -----------------
    function scroll_callback(~, event)
        delta = -event.VerticalScrollCount;
        change_slice(delta);
    end

    function key_callback(~, event)
        switch event.Key
            case 'uparrow'
                change_slice(1);
            case 'downarrow'
                change_slice(-1);
        end
    end

    function change_slice(delta)
        new_slice = current_slice + delta;
        if ~isempty(vol1) && new_slice >= 1 && new_slice <= size(vol1, 3)
            current_slice = new_slice;
            update_displayed_slices();
        end
    end

    % ----------------- Draw ROI -----------------
    function draw_roi()
        if isempty(h_circle1) || ~isvalid(h_circle1)
            h_circle1 = drawcircle(ax1, 'Color', 'r');
            h_circle2 = drawcircle(ax2, 'Center', h_circle1.Center, 'Radius', h_circle1.Radius, 'Color', 'r');
            addlistener(h_circle1, 'ROIMoved', @(src,evt) sync_circle(h_circle1, h_circle2));
        end
    end

    % ----------------- Update Display -----------------
    function update_displayed_slices()
        if isempty(vol1) || isempty(vol2)
            cla(ax1); title(ax1, 'Image 1 - No Subject Loaded');
            cla(ax2); title(ax2, 'Image 2 - No Subject Loaded');
            return;
        end
        img1 = vol1(:, :, current_slice);
        img2 = vol2(:, :, current_slice);

        image(ax1, img1 / 20);
        colormap(ax1, gray);
        axis(ax1, 'image');
        title(ax1, sprintf('Image 1 - Slice %d', current_slice));

        image(ax2, img2);
        colormap(ax2, gray);
        axis(ax2, 'image');
        title(ax2, sprintf('Image 2 - Slice %d', current_slice));

        if ~isempty(h_circle1) && isvalid(h_circle1)
            ax1.Children = [ax1.Children; h_circle1];
        end
        if ~isempty(h_circle2) && isvalid(h_circle2)
            ax2.Children = [ax2.Children; h_circle2];
        end
    end

    % ----------------- Submit Callback -----------------
    function submit_callback()
        if isempty(selected_subject_dir) || strcmp(selected_subject_dir, '--Select--')
            uialert(fig, 'Please choose a subject.', 'No Subject');
            return;
        end

        if strcmp(location_input.Value, '--Select--')
            uialert(fig, 'Please choose a location.', 'No Location');
            return;
        end

        if isempty(h_circle1) || ~isvalid(h_circle1)
            uialert(fig, 'Please draw a circle before submitting.', 'No ROI');
            return;
        end
    
        location = location_input.Value;
        location_title = replace(location, ' ', '_');
        img1_Hist = vol1_Hist(:, :, current_slice);
        img2_Hist = vol2_Hist(:, :, current_slice);
        mask = createMask(h_circle1);
        vals1 = double(img1_Hist(mask));
        vals2 = double(img2_Hist(mask));
        stats1 = [mean(vals1, 'omitnan'), max(vals1, [], 'omitnan'), min(vals1, [], 'omitnan')];
        stats2 = [mean(vals2, 'omitnan'), max(vals2, [], 'omitnan'), min(vals2, [], 'omitnan')];
    
        %% Make folders if missing
        if ~exist("Summary_Statistics", "dir")
            mkdir("Summary_Statistics");
        end
        if ~exist("Histograms", "dir")
            mkdir("Histograms");
        end
        if ~exist("ROI_Images", "dir")
            mkdir("ROI_Images");
        end
    
        %% Append to CSV in Summary_Statistics
        csv_path = fullfile("Summary_Statistics", location_title + ".csv");
        if ~isfile(csv_path)
            writetable(cell2table({"Subject", "Mean T1", "Maximum T1", "Minimum T1", "Mean T2", "Maximum T2", "MinimumT2"}), csv_path, 'WriteVariableNames', false);
        end
        new_row = {selected_subject_dir, stats1(1), stats1(2), stats1(3), stats2(1), stats2(2), stats2(3)};
        writecell(new_row, csv_path, 'WriteMode', 'append');
    
        %% Save histograms
        hist_dir = fullfile("Histograms", location, selected_subject_dir);
        if ~exist(hist_dir, "dir")
            mkdir(hist_dir);
        end
        
        f1 = figure('Visible', 'off');
        histogram(vals1); title("T1 " + location + " Histogram");
        saveas(f1, fullfile(hist_dir, "T1_Hist.png"));
        close(f1);
        
        f2 = figure('Visible', 'off');
        histogram(vals2); title("T2 " + location + " Histogram");
        saveas(f2, fullfile(hist_dir, "T2_Hist.png"));
        close(f2);
        
        %% Save ROI overlay images
        roi_dir = fullfile("ROI_Images", location, selected_subject_dir);
        if ~exist(roi_dir, "dir")
            mkdir(roi_dir);
        end
        
        % Save T1 with ROI
        f3 = figure('Visible', 'off');
        image(vol1(:,:,current_slice)/20); colormap(gray); axis image;
        hold on; viscircles(h_circle1.Center, h_circle1.Radius, 'Color', 'r');
        saveas(f3, fullfile(roi_dir, "T1_ROI.png"));
        close(f3);
        
        % Save T2 with ROI
        f4 = figure('Visible', 'off');
        image(vol2(:,:,current_slice)); colormap(gray); axis image;
        hold on; viscircles(h_circle2.Center, h_circle2.Radius, 'Color', 'r');
        saveas(f4, fullfile(roi_dir, "T2_ROI.png"));
        close(f4);
    
        %% Show Images
        figure('Name', sprintf('%s - ROI Histogram & Stats', location));
        tiledlayout(2,2);
    
        nexttile
        histogram(vals1);
        title(sprintf('%s - Image 1 (Slice %d)\nMin: %.1f, Max: %.1f, Mean: %.1f', ...
            location, current_slice, stats1(3), stats1(2), stats1(1)));
    
        nexttile
        histogram(vals2);
        title(sprintf('%s - Image 2 (Slice %d)\nMin: %.1f, Max: %.1f, Mean: %.1f', ...
            location, current_slice, stats2(3), stats2(2), stats2(1)));
    
        nexttile
        image(vol1(:,:,current_slice)/20);
        colormap(gray); axis image; hold on;
        viscircles(h_circle1.Center, h_circle1.Radius, 'Color', 'r');
        title(sprintf('%s - Image 1 with ROI', location));
    
        nexttile
        image(vol2(:,:,current_slice));
        colormap(gray); axis image; hold on;
        viscircles(h_circle2.Center, h_circle2.Radius, 'Color', 'r');
        title(sprintf('%s - Image 2 with ROI', location));
    end
end

% ----------------- Helper Functions -----------------
function sync_circle(c1, c2)
    if isvalid(c1) && isvalid(c2)
        c2.Center = c1.Center;
        c2.Radius = c1.Radius;
    end
end

function cleaned = apply_nan_thresholds(vol, lower_thresh, upper_thresh)
    [L, W, H] = size(vol);
    cleaned = vol;
    for i = 1:L
        for j = 1:W
            for k = 1:H
                if cleaned(i,j,k) < lower_thresh || cleaned(i,j,k) > upper_thresh
                    cleaned(i,j,k) = NaN;
                end
            end
        end
    end
end