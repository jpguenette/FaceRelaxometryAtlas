close all
clear all
clc

firstDir = 'ImagingData';
thirdDir = 'DICOMS';
fourthDir = ["T2_epi" "T1_epi" "T2_dlmupa/IMAGES" "T1_dlmupa/IMAGES" "T1w_tse/IMAGES"];

fileName = ["T2_epi.mat" "T1_epi.mat" "T2_dlmupa.mat" "T1_dlmupa.mat" "T1w_tse.mat"];

assert(length(fileName) == length(fourthDir));

numNewFiles = length(fourthDir);

allExams = dir(fullfile(firstDir, 'HF*'));

len = length(allExams);

for i = 1:len

    secondDir = allExams(i).name;

    for j = 1:numNewFiles
        dicomStruct = dir(fullfile(firstDir, secondDir, thirdDir, fourthDir(j)));
        dicomStruct = dicomStruct(~[dicomStruct.isdir]);
        dicomFiles = string({dicomStruct.name});

        totalSlices = numel(dicomFiles);
        exampleFile = fullfile(firstDir, secondDir, thirdDir, fourthDir(j), dicomFiles(1));
        firstSlice = dicomread(exampleFile);
        [height, width] = size(firstSlice);

        vol = zeros(height, width, totalSlices, 'like', firstSlice);

        for k = 1:totalSlices
            filePath = fullfile(firstDir, secondDir, thirdDir, fourthDir(j), dicomFiles(k));
            vol(:,:,k) = dicomread(filePath);
        end
        
        if j > 2
            vol = permute(vol, [2 3 1]);
            vol = flip(vol, 2);
            vol = flip(vol, 3);
        end

        save(fullfile(firstDir, secondDir, fileName(j)),'vol');
    end
end