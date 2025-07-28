function draw_and_analyze_roi(file1, file2, slice_index)
    % Load the two 3D image matrices from the given .mat files
    data1 = load(file1);
    data2 = load(file2);

    % Extract the image variables
    fields1 = fieldnames(data1);
    fields2 = fieldnames(data2);
    vol1 = data1.(fields1{1});
    vol2 = data2.(fields2{1});

    % Apply same voxel-by-voxel cleaning
    vol1_Hist = apply_nan_thresholds(vol1, 100, 2500);
    vol2_Hist = apply_nan_thresholds(vol2, 10, 300);

    % Validate inputs
    if ~isequal(size(vol1), size(vol2))
        error('3D volumes must have the same dimensions.');
    end
    if ndims(vol1) ~= 3
        error('Both inputs must be 3D image volumes.');
    end
    if slice_index < 1 || slice_index > size(vol1, 3)
        error('slice_index must be between 1 and %d', size(vol1, 3));
    end

    % Extract the selected slice
    img1 = vol1(:, :, slice_index);
    img2 = vol2(:, :, slice_index);

    img1_Hist = vol1_Hist(:, :, slice_index);
    img2_Hist = vol2_Hist(:, :, slice_index);

    % Create UI
    fig = uifigure('Name', 'ROI Drawing Tool', 'Position', [100 100 1200 600]);
    gl = uigridlayout(fig, [2 2]);
    gl.RowHeight = {'1x', 50};
    gl.ColumnWidth = {'1x', '1x'};

    % Axes for images
    ax1 = uiaxes(gl);
    ax2 = uiaxes(gl);
    
    % Display Image 1
    image(ax1, img1 / 20);            % same scaling as your standalone example
    colormap(ax1, gray);              % ensure grayscale
    axis(ax1, 'image');               % keep aspect ratio square
    title(ax1, sprintf('Image 1 - Slice %d', slice_index));
    
    % Display Image 2
    image(ax2, img2);
    colormap(ax2, gray);
    axis(ax2, 'image');
    title(ax2, sprintf('Image 2 - Slice %d', slice_index));

    % Submit button
    btn = uibutton(gl, 'Text', 'Submit', 'ButtonPushedFcn', @(btn,event)submit_callback());
    btn.Layout.Row = 2;
    btn.Layout.Column = [1 2];

    % Draw circle on first image
    h_circle1 = drawcircle(ax1, 'Color', 'r');
    h_circle2 = drawcircle(ax2, 'Center', h_circle1.Center, 'Radius', h_circle1.Radius, 'Color', 'r');

    % Update second circle in real-time
    addlistener(h_circle1, 'ROIMoved', @(src,evt) sync_circle(h_circle1, h_circle2));

    function submit_callback()
        % Create mask from ROI
        mask = createMask(h_circle1);

        % Extract pixel values from both images inside the ROI
        vals1 = double(img1_Hist(mask));
        vals2 = double(img2_Hist(mask));

        % Compute statistics
        stats1 = [min(vals1, [], 'omitnan'), ...
          max(vals1, [], 'omitnan'), ...
          mean(vals1, 'omitnan')];
        
        stats2 = [min(vals2, [], 'omitnan'), ...
          max(vals2, [], 'omitnan'), ...
          mean(vals2, 'omitnan')];

        % Display stats and histograms
        figure('Name', 'ROI Histogram & Stats');
        tiledlayout(2,2);

        nexttile
        histogram(vals1);
        title(sprintf('Image 1 (Slice %d)\nMin: %.1f, Max: %.1f, Mean: %.1f', ...
            slice_index, stats1));

        nexttile
        histogram(vals2);
        title(sprintf('Image 2 (Slice %d)\nMin: %.1f, Max: %.1f, Mean: %.1f', ...
            slice_index, stats2));

        nexttile
        image(img1 / 20);
        colormap(gray);
        axis image;
        hold on; viscircles(h_circle1.Center, h_circle1.Radius, 'Color', 'r');
        title('Image 1 with ROI');
        
        nexttile
        image(img2);
        colormap(gray);
        axis image;
        hold on; viscircles(h_circle2.Center, h_circle2.Radius, 'Color', 'r');
        title('Image 2 with ROI');
    end
end

function sync_circle(c1, c2)
    c2.Center = c1.Center;
    c2.Radius = c1.Radius;
end

function cleaned = apply_nan_thresholds(vol, lower_thresh, upper_thresh)
    [L, W, H] = size(vol);
    cleaned = vol;  % make a copy for editing

    for i = 1:L
        for j = 1:W
            for k = 1:H
                if cleaned(i,j,k) < lower_thresh
                    cleaned(i,j,k) = NaN;
                elseif cleaned(i,j,k) > upper_thresh
                    cleaned(i,j,k) = NaN;
                else
                    cleaned(i,j,k) = cleaned(i,j,k);  % redundant, but kept for fidelity
                end
            end
        end
    end
end