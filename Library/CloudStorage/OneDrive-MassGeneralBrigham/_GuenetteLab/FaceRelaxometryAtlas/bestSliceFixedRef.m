function [best_dx, best_small_slice, best_MI] = bestSliceFixedRef(small, big, big_slice)

    best_MI = 0;
    best_dx = 0;
    best_small_slice = 1;

    W = size(small,2);

    for small_slice = 1:size(small,3)
        for dx = 0:(size(big,2) - W)
            MI = mutualInfo(mat2gray(big(:,dx+1:dx+W,big_slice)), mat2gray(small(:,:,small_slice)));
            if MI > best_MI
                best_MI = MI;
                best_dx = dx;
                best_small_slice = small_slice;
            end
        end
    end
end