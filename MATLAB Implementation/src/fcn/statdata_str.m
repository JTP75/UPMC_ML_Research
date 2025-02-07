function s = statdata_str(Arr)
s = ...
    "1d Array statistical info:" + ...
    "\nmean: " + mean(Arr) + ...
    "\nstandard deviation: " + std(Arr) + ...
    "\nmedian: " + median(Arr) + ...
    "\nmin: " + min(Arr) + ...
    "\nmax: " + max(Arr) + ...
    "\nrange: " + (max(Arr)-min(Arr)) + ...
    "\n\n";

