function Acell = mat2cellR(A)
Acell = cell(size(A,2),1);
for i = 1:size(A,2)
    Acell{i,1} = A(:,i);
end