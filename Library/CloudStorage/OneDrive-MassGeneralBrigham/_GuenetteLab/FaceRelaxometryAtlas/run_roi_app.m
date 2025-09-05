function run_roi_app(locations_path, slice_index)
    if nargin < 2 || isempty(slice_index), slice_index = 1; end

    % ---------- Subject & Location dropdown data ----------
    baseImDir = fullfile(pwd, 'ImagingData');
    subj_items = ["--Select--"];                
    subj_data  = {[]};                          

    if isfolder(baseImDir)
        d = dir(fullfile(baseImDir, 'HF*'));
        d = d([d.isdir]);
        names = string({d.name});
        if ~isempty(names)
            subj_items = ["--Select--"; names(:)];
            fullpaths = cellstr(fullfile(baseImDir, cellstr(names(:))));
            subj_data = [{[]}, fullpaths'];
        end
    else
        warning('ImagingData folder not found at: %s', baseImDir);
    end

    if nargin >= 1 && ~isempty(locations_path) && isfile(locations_path)
        loc = readlines(locations_path);
        loc = strtrim(loc); loc = loc(strlength(loc) > 0);
    else
        loc = string.empty(0,1);
    end
    loc_items = ["--Select--"; loc(:)];

    % ---------- Root figure & root grid ----------
    fig = uifigure('Name','ROI Suite', 'Position',[80 80 1600 900]);

    try
        fig.WindowState = 'maximized';
    catch
        s = get(groot,'ScreenSize');   % [left bottom width height]
        fig.Position = s;
    end

    root = uigridlayout(fig, [3 2]);
    root.RowHeight     = {86, '1x', 70};
    root.ColumnWidth   = {'1x','1x'};
    root.Padding       = [10 10 10 10];
    root.RowSpacing    = 8;
    root.ColumnSpacing = 8;

    % ---------- TOP: labels ABOVE dropdowns ----------
    topLeft  = uigridlayout(root,[2 1]);
    topLeft.RowHeight   = {24, '1x'};
    topLeft.ColumnWidth = {'1x'};
    topLeft.Padding     = [0 0 0 0];
    topLeft.RowSpacing  = 6;
    topLeft.Layout.Row = 1; topLeft.Layout.Column = 1;

    uilabel(topLeft,'Text','Subject:','HorizontalAlignment','left','FontWeight','bold');

    dd_subject = uidropdown(topLeft, ...
        'Items',      cellstr(subj_items), ...
        'ItemsData',  subj_data, ...
        'Value',      subj_data{1}, ...
        'Tooltip',    'Choose an HF* subject from ImagingData', ...
        'ValueChangedFcn', @(dd,ev) on_subject_changed(dd, fig));
    
    topRight = uigridlayout(root,[2 1]);
    topRight.RowHeight   = {24, '1x'};
    topRight.ColumnWidth = {'1x'};
    topRight.Padding     = [0 0 0 0];
    topRight.RowSpacing  = 6;
    topRight.Layout.Row = 1; topRight.Layout.Column = 2;

    uilabel(topRight,'Text','Location:','HorizontalAlignment','left','FontWeight','bold');
    dd_location = uidropdown(topRight,'Items',cellstr(loc_items),'Value',loc_items(1));
    dd_location.ValueChangedFcn = @(dd,ev) update_submit_enabled();

    % ---------- MIDDLE: 5 axes in a 1x5 grid ----------
    midPanel = uipanel(root); midPanel.Layout.Row = 2; midPanel.Layout.Column = [1 2];
    midPanel.BorderType = 'none';

    mid = uigridlayout(midPanel,[1 5]);
    mid.Padding       = [0 0 0 0];
    mid.RowSpacing    = 0;
    mid.ColumnSpacing = 8;

    ax_T1_dlmupa = uiaxes(mid);  setup_axis(ax_T1_dlmupa,'T1_dlmupa (controller)');
    ax_T1_epi    = uiaxes(mid);  setup_axis(ax_T1_epi   ,'T1_epi');
    ax_T2_dlmupa = uiaxes(mid);  setup_axis(ax_T2_dlmupa,'T2_dlmupa');
    ax_T2_epi    = uiaxes(mid);  setup_axis(ax_T2_epi   ,'T2_epi');
    ax_T1w_tse   = uiaxes(mid);  setup_axis(ax_T1w_tse  ,'T1w_tse');

    % ---------- BOTTOM: two buttons ----------
    btn_draw = uibutton(root,'Text','Draw ROI');
    btn_draw.Layout.Row = 3; btn_draw.Layout.Column = 1;
    btn_draw.ButtonPushedFcn = @(b,ev) on_draw_roi(fig);

    btn_submit = uibutton(root,'Text','Submit');
    btn_submit.Layout.Row = 3; btn_submit.Layout.Column = 2;
    btn_submit.ButtonPushedFcn = @(b,ev) on_submit(fig);

    % ---------- Aspect-preserving resize (scaffold) ----------
    fig.AutoResizeChildren = 'off';
    fig.SizeChangedFcn = @(src,ev) apply_mid_aspect();
    apply_mid_aspect();

    % ---------- Stash ----------
    S = struct();
    S.slice_index  = slice_index;
    S.dd_subject   = dd_subject;
    S.dd_location  = dd_location;
    S.ax = struct('T1_dlmupa',ax_T1_dlmupa,'T1_epi',ax_T1_epi, ...
                  'T2_dlmupa',ax_T2_dlmupa,'T2_epi',ax_T2_epi,'T1w_tse',ax_T1w_tse);
    S.selected_subject_path = '';
    S.selected_subject_name = '';
    fig.UserData = S;

    % --- Enable scrolling (wheel) and arrow keys ---
    fig.WindowScrollWheelFcn = @(~,ev) on_scroll(ev);
    fig.KeyPressFcn = @(~,ev) on_key(ev);

    % ================= Helpers =================
    function setup_axis(ax, ttl)
        ax.XTick = []; ax.YTick = [];
        ax.Toolbar = [];
        box(ax,'on');
        axis(ax,'image');
        colormap(ax, gray);
        title(ax, [ttl ' — No Subject Loaded'],'Interpreter','none');
    end

    function apply_mid_aspect()
        mid.ColumnWidth = {'1x','1x','1x','1x','1x'};
        mid.RowHeight   = {'1x'};
        axs = [ax_T1_dlmupa, ax_T1_epi, ax_T2_dlmupa, ax_T2_epi, ax_T1w_tse];
        for k = 1:numel(axs)
            pbaspect(axs(k), [256 176 1]);   % visual hint only
        end
    end

    function on_subject_changed(dd, figH)
        clear_roi();
        subjPath = dd.Value;               % [] if "--Select--"
        S = figH.UserData;
    
        % Clear when unselected
        if isempty(subjPath)
            S.selected_subject_path = '';
            S.selected_subject_name = '';
            S.V = []; S.align = []; S.sSmall = [];
            figH.UserData = S;
            cla(ax_T1_dlmupa); cla(ax_T1_epi); cla(ax_T2_dlmupa); cla(ax_T2_epi); cla(ax_T1w_tse);
            title(ax_T1_dlmupa,'T1_dlmupa (controller) — No Subject Loaded','Interpreter','none');
            title(ax_T1_epi   ,'T1_epi — No Subject Loaded','Interpreter','none');
            title(ax_T2_dlmupa,'T2_dlmupa — No Subject Loaded','Interpreter','none');
            title(ax_T2_epi   ,'T2_epi — No Subject Loaded','Interpreter','none');
            title(ax_T1w_tse  ,'T1w_tse — No Subject Loaded','Interpreter','none');
            return;
        end
    
        [~, subjName] = fileparts(subjPath);
        S.selected_subject_path = subjPath;
        S.selected_subject_name = subjName;
    
        % --- Load volumes ---
        try
            T1_dlmupa = load_first_var(fullfile(subjPath, 'T1_dlmupa.mat'));  % 256x176x256
            T1_epi    = load_first_var(fullfile(subjPath, 'T1_epi.mat'));     % 256x256x10
            T2_dlmupa = load_first_var(fullfile(subjPath, 'T2_dlmupa.mat'));  % 256x176x256
            T2_epi    = load_first_var(fullfile(subjPath, 'T2_epi.mat'));     % 256x256x10
            T1w_tse_o = load_first_var(fullfile(subjPath, 'T1w_tse.mat'));    % 512x176x512
        catch ME
            uialert(figH, sprintf('Error loading subject %s:\n%s', subjName, ME.message), 'Load Error');
            return;
        end
    
        % --- Downsample T1w_tse -> 256x176x256 (every other slice, then rows x0.5) ---
        try
            T1w_tse = downsample_t1w_tse(T1w_tse_o);
        catch ME
            uialert(figH, sprintf('T1w\\_tse resizing error:\n%s', ME.message), 'Resize Error');
            return;
        end
    
        % --- Alignment using your function ---
        try
            [best_dx, best_small_slice, ~] = bestSliceFixedRef(T1_dlmupa, T1_epi, S.slice_index);
        catch ME
            uialert(figH, sprintf('bestSliceFixedRef error:\n%s', ME.message), 'Alignment Error');
            return;
        end
    
        % Precompute EPI crop columns (your function ensures valid range)
        cols = (best_dx + 1) : (best_dx + size(T1_dlmupa,2));   % 176-wide
    
        % --- Persist everything needed for scrolling ---
        S.V = struct('T1_dlmupa',T1_dlmupa, 'T1_epi',T1_epi, 'T2_dlmupa',T2_dlmupa, ...
                     'T2_epi',T2_epi, 'T1w_tse',T1w_tse);
        S.align = struct('best_dx',best_dx, 'best_small',best_small_slice, ...
                         'cols',cols, 'big_slice',S.slice_index);
        S.sSmall = best_small_slice;  % controller starts at best_small_slice
        figH.UserData = S;
    
        % --- Initial draw ---
        update_images();
        update_submit_enabled();
    end

    function vol = load_first_var(matPath)
        if ~isfile(matPath)
            error('Missing file: %s', matPath);
        end
        data = load(matPath);
        f = fieldnames(data);
        if isempty(f), error('No variables in %s', matPath); end
        vol = data.(f{1});
    end

    function show2D(ax, img, ttl)
        % Autoscale like imshow(img, []), robust to NaNs/constant images
        finiteVals = img(isfinite(img));
        if isempty(finiteVals)
            dr = [0 1];
        else
            vmin = min(finiteVals(:), [], 'omitnan');
            vmax = max(finiteVals(:), [], 'omitnan');
            if vmin == vmax
                epsv = max(1, abs(vmin)*1e-6);
                dr = [vmin - epsv, vmax + epsv];
            else
                dr = [vmin, vmax];
            end
        end
    
        imshow(img, dr, 'Parent', ax);   % same effect as imshow(img, [])
        colormap(ax, gray);
        axis(ax, 'image');
        ax.XTick = []; ax.YTick = [];
        title(ax, ttl, 'Interpreter','none');
    end

    function on_draw_roi(figH)
        % Require data to be loaded
        S = figH.UserData;
        if ~isfield(S,'V') || isempty(S.V)
            uialert(figH,'Load a subject first.','No Data');
            return;
        end
    
        % Clear any existing ROI first
        clear_roi();
    
        % Create the interactive ROI on the LEFTMOST axis only
        h = drawcircle(ax_T1_dlmupa, 'Color','r', 'LineWidth',1.5, ...
                       'FaceAlpha',0.05);   % user draws now
    
        % Stash ROI state
        S = figH.UserData;
        S.roi = struct('main', h, 'clones', struct(), 'listeners', []);
        figH.UserData = S;
    
        % Mirror ROI while moving and after moved
        L1 = addlistener(h, 'MovingROI', @(src,evt) sync_roi(src));
        L2 = addlistener(h, 'ROIMoved',  @(src,evt) sync_roi(src));
        % If user deletes the ROI manually, clean up clones too (if event exists)
        try
            L3 = addlistener(h, 'DeletingROI', @(src,evt) clear_roi());
        catch
            L3 = [];
        end
    
        S = figH.UserData;
        S.roi.listeners = [L1 L2 L3];
        figH.UserData = S;
    
        % Initial mirror once the circle exists
        sync_roi(h);
        update_submit_enabled();
    end

    function on_submit(figH)
        S = figH.UserData;
    
        % Guardrails (should already be enforced by button enabling)
        if ~isfield(S,'V') || isempty(S.V)
            uialert(figH,'Load a subject first.','No Data'); return;
        end
        if strcmp(dd_location.Value,'--Select--')
            uialert(figH,'Choose a location first.','No Location'); return;
        end
        if ~isfield(S,'roi') || isempty(S.roi) || isempty(S.roi.main) || ~isvalid(S.roi.main)
            uialert(figH,'Draw an ROI first.','No ROI'); return;
        end
    
        % Indices/slices to use (current controller & mapped EPI)
        sSmall = S.sSmall;
        maxEPI = size(S.V.T1_epi,3);
        sEPI   = map_small_to_epi(sSmall, S.align.best_small, S.align.big_slice, maxEPI);
        cols   = S.align.cols;  % EPI crop columns from best_dx
    
        % Extract images for this submit
        I_T1_dlmupa = S.V.T1_dlmupa(:,:,sSmall);
        I_T1_epi    = S.V.T1_epi(:,cols,sEPI);
        I_T2_dlmupa = S.V.T2_dlmupa(:,:,sSmall);
        I_T2_epi    = S.V.T2_epi(:,cols,sEPI);
        I_T1w_tse   = S.V.T1w_tse(:,:,sSmall);
    
        % ROI mask from left-most interactive circle
        mask = createMask(S.roi.main);   % same geometry across all 256x176 views

        % T1_thresh = [100 2500];
        % T2_thresh = [10 300];

        % Collect values (double, omit NaNs)
        vals = struct();
        vals.T1_dlmupa = double(I_T1_dlmupa(mask));
        % vals.T1_dlmupa(vals.T1_dlmupa < T1_thresh(1) | vals.T1_dlmupa > T1_thresh(2)) = NaN;

        vals.T1_epi    = double(I_T1_epi(mask));
        % vals.T1_epi(vals.T1_epi < T1_thresh(1) | vals.T1_epi > T1_thresh(2)) = NaN;

        vals.T2_dlmupa = double(I_T2_dlmupa(mask));
        % vals.T2_dlmupa(vals.T2_dlmupa < T2_thresh(1) | vals.T2_dlmupa > T2_thresh(2)) = NaN;

        vals.T2_epi    = double(I_T2_epi(mask));
        % vals.T2_epi(vals.T2_epi < T2_thresh(1) | vals.T2_epi > T2_thresh(2)) = NaN;

        vals.T1w_tse   = double(I_T1w_tse(mask));
    
        % Stats
        stats = @(v)[mean(v,'omitnan'), max(v,[],'omitnan'), min(v,[],'omitnan')];
        s_T1_dlmupa = stats(vals.T1_dlmupa);
        s_T1_epi    = stats(vals.T1_epi);
        s_T2_dlmupa = stats(vals.T2_dlmupa);
        s_T2_epi    = stats(vals.T2_epi);
        s_T1w_tse   = stats(vals.T1w_tse);
    
        % ---------- Big summary figure: top=histograms, bottom=overlays ----------
        f = figure('Name','ROI Summary','Units','normalized','Position',[0.02 0.06 0.96 0.86]);
        tl = tiledlayout(f,2,5,'TileSpacing','compact','Padding','compact');
    
        % nice title helper
        statstr = @(m) sprintf('Mean %.2f | Max %.2f | Min %.2f', m(1), m(2), m(3));
    
        % Histograms (top row)
        nexttile; beaut_hist(vals.T1_dlmupa, 'T1_dlmupa', s_T1_dlmupa);
        nexttile; beaut_hist(vals.T1_epi,    'T1_epi',    s_T1_epi);
        nexttile; beaut_hist(vals.T2_dlmupa, 'T2_dlmupa', s_T2_dlmupa);
        nexttile; beaut_hist(vals.T2_epi,    'T2_epi',    s_T2_epi);
        nexttile; beaut_hist(vals.T1w_tse,   'T1w_tse',   s_T1w_tse);
    
        % Overlays (bottom row) — reuse ROI center/radius
        c = S.roi.main.Center; r = S.roi.main.Radius;
        nexttile; overlay_with_circle(I_T1_dlmupa, c, r, sprintf('T1_dlmupa Slice %d', sSmall));
        nexttile; overlay_with_circle(I_T1_epi   , c, r, sprintf('T1_epi Slice %d', sEPI));
        nexttile; overlay_with_circle(I_T2_dlmupa, c, r, sprintf('T2_dlmupa Slice %d', sSmall));
        nexttile; overlay_with_circle(I_T2_epi   , c, r, sprintf('T2_epi Slice %d', sEPI));
        nexttile; overlay_with_circle(I_T1w_tse  , c, r, sprintf('T1w_tse Slice %d', sSmall));
    
        % ---------- Save histograms and ROI overlays ----------
        subj  = S.selected_subject_name;
        loc   = dd_location.Value;
        rootH = fullfile('data','histograms',loc,subj);
        rootR = fullfile('data','ROIs',       loc,subj);
        if ~exist(rootH,'dir'); mkdir(rootH); end
        if ~exist(rootR,'dir'); mkdir(rootR); end
    
        % Save individual histogram PNGs (fresh figures, no overwrite)
        save_hist_png(vals.T1_dlmupa, 'T1_dlmupa', s_T1_dlmupa, fullfile(rootH,'T1_dlmupa_histogram.png'));
        save_hist_png(vals.T1_epi,    'T1_epi',    s_T1_epi,    fullfile(rootH,'T1_epi_histogram.png'));
        save_hist_png(vals.T2_dlmupa, 'T2_dlmupa', s_T2_dlmupa, fullfile(rootH,'T2_dlmupa_histogram.png'));
        save_hist_png(vals.T2_epi,    'T2_epi',    s_T2_epi,    fullfile(rootH,'T2_epi_histogram.png'));
        % save_hist_png(vals.T1w_tse,   'T1w_tse',   s_T1w_tse,   fullfile(rootH,'T1w_tse_histogram.png'));
    
        % Save ROI overlay PNGs
        save_overlay_png(I_T1_dlmupa, c, r, fullfile(rootR,'T1_dlmupa_ROI.png'));
        save_overlay_png(I_T1_epi,    c, r, fullfile(rootR,'T1_epi_ROI.png'));
        save_overlay_png(I_T2_dlmupa, c, r, fullfile(rootR,'T2_dlmupa_ROI.png'));
        save_overlay_png(I_T2_epi,    c, r, fullfile(rootR,'T2_epi_ROI.png'));
        save_overlay_png(I_T1w_tse,   c, r, fullfile(rootR,'T1w_tse_ROI.png'));
    
        % ---------- Append to CSV and sort by Subject ----------
        csvDir = fullfile('data','summary_statistics');
        if ~exist(csvDir,'dir'); mkdir(csvDir); end
        csvPath = fullfile(csvDir, [loc '.csv']);
        
        headers = ["Subject", ...
            "T1_dlmupa Mean","T1_dlmupa Max","T1_dlmupa Min", ...
            "T1_epi Mean","T1_epi Max","T1_epi Min", ...
            "T2_dlmupa Mean","T2_dlmupa Max","T2_dlmupa Min", ...
            "T2_epi Mean","T2_epi Max","T2_epi Min", ...
            "T1w_tse Mean","T1w_tse Max","T1w_tse Min"];
        
        newRow = {subj, ...
            s_T1_dlmupa(1), s_T1_dlmupa(2), s_T1_dlmupa(3), ...
            s_T1_epi(1),    s_T1_epi(2),    s_T1_epi(3), ...
            s_T2_dlmupa(1), s_T2_dlmupa(2), s_T2_dlmupa(3), ...
            s_T2_epi(1),    s_T2_epi(2),    s_T2_epi(3), ...
            s_T1w_tse(1),   s_T1w_tse(2),   s_T1w_tse(3)};
        
        % --- FIX: keep header as a 1x16 row cell (no transpose) ---
        headerRow = cellstr(headers);   % 1x16 cell row
        
        % Create or append
        if ~isfile(csvPath)
            writecell([headerRow; newRow], csvPath);
        else
            writecell(newRow, csvPath, 'WriteMode','append');
        end
        
        % Re-open, keep header, sort DATA rows by Subject
        C = readcell(csvPath);
        if size(C,1) >= 2
            hdr  = C(1,:);          % 1x16
            data = C(2:end,:);      % Nx16
        
            varNames = matlab.lang.makeValidName(headerRow);
            T = cell2table(data, 'VariableNames', varNames);
            T = sortrows(T, 'Subject');
            writecell([hdr; table2cell(T)], csvPath);
        end
    
        % Done — keep the summary figure open
    end

    function V256 = downsample_t1w_tse(V)
    % Input V expected ~512x176x512 (rows x cols x slices)
    % Output V256 is 256x176x256:
    %   - Z: take every other slice
    %   - Rows: downsample by 0.5 (512 -> 256)
    
        % Keep every other slice
        Vz = V(:,:,1:2:end);   % size ~ 512 x 176 x 256
    
        % Downsample rows
        targetSize = [256, size(Vz,2), size(Vz,3)];  % [rows cols slices]

        V256 = imresize3(Vz, targetSize, 'linear');

        %{
        USE IF imresize3 DOESN"T EXIST
        % Fallback: resize each slice in 2D
        V256 = zeros(targetSize, class(Vz));
        for k = 1:targetSize(3)
            V256(:,:,k) = imresize(Vz(:,:,k), [targetSize(1) targetSize(2)], 'bilinear');
        end
        %}
    end

    function sEPI = map_small_to_epi(currentSmall, bestSmall, big_slice, maxEPI)
        % 15-slice windows, inclusive; center window maps to big_slice
        offset = floor((currentSmall - bestSmall + 7) / 15);
        sEPI = big_slice + offset;
        sEPI = max(1, min(maxEPI, sEPI));   % clamp to [1..10]
    end

    function update_images()
        S = fig.UserData;
        if ~isfield(S,'V') || isempty(S.V), return; end
    
        % Controller (small stack) slice
        sSmall = S.sSmall;
        nSmall = size(S.V.T1_dlmupa, 3);
        sSmall = max(1, min(nSmall, sSmall));  % guard
        S.sSmall = sSmall; fig.UserData = S;
    
        % Map to EPI slice
        maxEPI = size(S.V.T1_epi, 3);  % typically 10
        sEPI = map_small_to_epi(sSmall, S.align.best_small, S.align.big_slice, maxEPI);
    
        % Extract images per spec
        img_T1_dlmupa = S.V.T1_dlmupa(:,:,sSmall);
        img_T2_dlmupa = S.V.T2_dlmupa(:,:,sSmall);
        img_T1w_tse   = S.V.T1w_tse(:,:,sSmall);
    
        img_T1_epi = S.V.T1_epi(:, S.align.cols, sEPI);
        img_T2_epi = S.V.T2_epi(:, S.align.cols, sEPI);
    
        % Draw
        show2D(ax_T1_dlmupa, img_T1_dlmupa, sprintf('T1_dlmupa — %s (slice %d)', S.selected_subject_name, sSmall));
        show2D(ax_T1_epi   , img_T1_epi   , sprintf('T1_epi — %s (EPI slice %d)', S.selected_subject_name, sEPI));
        show2D(ax_T2_dlmupa, img_T2_dlmupa, sprintf('T2_dlmupa — %s (slice %d)', S.selected_subject_name, sSmall));
        show2D(ax_T2_epi   , img_T2_epi   , sprintf('T2_epi — %s (EPI slice %d)', S.selected_subject_name, sEPI));
        show2D(ax_T1w_tse  , img_T1w_tse  , sprintf('T1w_tse — %s (slice %d)', S.selected_subject_name, sSmall));
    end

    function on_scroll(ev)
        if ~isfield(fig.UserData,'V') || isempty(fig.UserData.V), return; end
        % Any scroll clears the ROI
        clear_roi();
        update_submit_enabled();
    
        delta = -ev.VerticalScrollCount;   % wheel up -> +1, down -> -1
        if delta == 0, return; end
        S = fig.UserData;
        S.sSmall = S.sSmall + delta;
        fig.UserData = S;
        update_images();
    end
    
    function on_key(ev)
        if ~isfield(fig.UserData,'V') || isempty(fig.UserData.V), return; end
        switch ev.Key
            case 'uparrow',   delta = +1;
            case 'downarrow', delta = -1;
            otherwise, return;
        end
        % Any arrow-key slice change clears the ROI
        clear_roi();
        update_submit_enabled();
    
        S = fig.UserData;
        S.sSmall = S.sSmall + delta;
        fig.UserData = S;
        update_images();
    end

    function sync_roi(hMain)
        % Mirror the left ROI onto the other four axes as non-interactive red circles
        if isempty(hMain) || ~isvalid(hMain), return; end
    
        S = fig.UserData;
        if ~isfield(S,'roi') || isempty(S.roi), return; end
    
        c = hMain.Center;
        r = hMain.Radius;
    
        % Delete old clones
        if isfield(S.roi,'clones') && ~isempty(S.roi.clones)
            fns = fieldnames(S.roi.clones);
            for i = 1:numel(fns)
                h = S.roi.clones.(fns{i});
                if isgraphics(h), delete(h); end
            end
        end
    
        % Draw fresh, non-interactive clones using rectangle-with-curvature
        pos = [c(1)-r, c(2)-r, 2*r, 2*r];
        S.roi.clones = struct();
    
        targets = { ...
            'T1_epi',    ax_T1_epi; ...
            'T2_dlmupa', ax_T2_dlmupa; ...
            'T2_epi',    ax_T2_epi; ...
            'T1w_tse',   ax_T1w_tse };
    
        for k = 1:size(targets,1)
            ax = targets{k,2};
            hold(ax,'on');
            hClone = rectangle(ax, 'Position', pos, 'Curvature',[1 1], ...
                'EdgeColor','r', 'LineWidth',1.5, 'HitTest','off', 'PickableParts','none');
            hold(ax,'off');
            try, uistack(hClone,'top'); end %#ok<TRYNC>
            S.roi.clones.(targets{k,1}) = hClone;
        end
    
        fig.UserData = S;
    end
    
    function clear_roi()
        % Remove main ROI, any clone overlays, and listeners
        S = fig.UserData;
        if ~isfield(S,'roi') || isempty(S.roi), return; end
    
        % listeners
        if isfield(S.roi,'listeners') && ~isempty(S.roi.listeners)
            for L = S.roi.listeners
                if ~isempty(L) && isvalid(L), delete(L); end
            end
        end
        % main ROI
        if isfield(S.roi,'main') && ~isempty(S.roi.main) && isvalid(S.roi.main)
            if isvalid(S.roi.main), delete(S.roi.main); end
        end
        % clones
        if isfield(S.roi,'clones') && ~isempty(S.roi.clones)
            fns = fieldnames(S.roi.clones);
            for i = 1:numel(fns)
                h = S.roi.clones.(fns{i});
                if isgraphics(h), delete(h); end
            end
        end
    
        S.roi = [];
        fig.UserData = S;
    end

    function update_submit_enabled()
        S = fig.UserData;
        hasSubject  = isfield(S,'selected_subject_path') && ~isempty(S.selected_subject_path);
        hasLocation = ~strcmp(dd_location.Value, '--Select--');
        hasROI      = isfield(S,'roi') && ~isempty(S.roi) && isfield(S.roi,'main') && ~isempty(S.roi.main) && isvalid(S.roi.main);
        btn_submit.Enable = ternary(hasSubject && hasLocation && hasROI, 'on', 'off');
    end
    
    function out = ternary(cond, a, b)
        if cond, out = a; else, out = b; end
    end

    function beaut_hist(v, titleStr, statvec)
        finiteV = v(isfinite(v));
        if isempty(finiteV), finiteV = 0; end
        histogram(finiteV, 'EdgeColor','none'); grid on; box on;
        title({titleStr; sprintf('Mean %.2f | Max %.2f | Min %.2f', statvec(1), statvec(2), statvec(3))}, 'Interpreter','none');
        xlabel('Value'); ylabel('Count');
    end
    
    function overlay_with_circle(img, ctr, rad, ttl)
        imshow(img, [], 'Border','tight'); hold on;
        rectangle('Position',[ctr(1)-rad, ctr(2)-rad, 2*rad, 2*rad], 'Curvature',[1 1], ...
                  'EdgeColor','r','LineWidth',1.5);
        title(ttl, 'Interpreter','none'); hold off;
    end
    
    function save_hist_png(v, nameStr, statvec, path0)
        figH = figure('Visible','off'); 
        histogram(v(isfinite(v)), 'EdgeColor','none'); grid on; box on;
        title({[nameStr ' histogram']; sprintf('Mean %.2f | Max %.2f | Min %.2f', statvec(1), statvec(2), statvec(3))}, 'Interpreter','none');
        xlabel('Value'); ylabel('Count');
        fp = unique_path(path0);
        exportgraphics(gca, fp, 'Resolution', 150);
        close(figH);
    end
    
    function save_overlay_png(img, ctr, rad, path0)
        figH = figure('Visible','off'); 
        imshow(img, []); hold on;
        rectangle('Position',[ctr(1)-rad, ctr(2)-rad, 2*rad, 2*rad], 'Curvature',[1 1], ...
                  'EdgeColor','r','LineWidth',1.5);
        hold off;
        fp = unique_path(path0);
        exportgraphics(gca, fp, 'Resolution', 150);
        close(figH);
    end
    
    function fp = unique_path(p0)
        % "mac-like" non-overwriting: "name (1).png", "name (2).png", ...
        [p,f,e] = fileparts(p0);
        k = 0;
        fp = p0;
        while exist(fp,'file')
            k = k + 1;
            fp = fullfile(p, sprintf('%s (%d)%s', f, k, e));
        end
    end
end