% ------------------------------------------------------------------------------
% Read a 'gli' or 'pl1' CSV file from a sea explorer and store the data in an
% output matlab structure.
%
% SYNTAX :
%  [o_dataStruct] = gl_read_seaexplorer_csv(a_csvFileNameIn)
%
% INPUT PARAMETERS :
%   a_csvFileNameIn  : name of the 'gli' or 'pl1' CSV file of data
%
% OUTPUT PARAMETERS :
%   o_dataStruct : output structure
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   09/09/2014 - RNU - creation
% ------------------------------------------------------------------------------
function [o_dataStruct] = gl_read_seaexplorer_csv(a_csvFileNameIn)

% output parameter initialization
o_dataStruct = '';

% shift between Julian days and matlab dates
SHIFT_DATE = 712224;

% to convert Julian Day 1950 into EPOCH 1970
EPOCH_OFFSET = 7305; % datenum(1970, 1, 1) - datenum(1950, 1, 1);

% EPOCH 1970 of January 1st 2000
EPOCH_01_01_2000 = 946684800;


% check if the file exists
if (~exist(a_csvFileNameIn, 'file'))
   fprintf('ERROR: File not found : %s\n', a_csvFileNameIn);
   return
end

% open the file
fIdIn = fopen(a_csvFileNameIn, 'r');
if (fIdIn == -1)
   fprintf('ERROR: While openning file : %s\n', a_csvFileNameIn);
   return
end

% read the data
lines = [];
while 1
   line = fgetl(fIdIn);
   if (line == -1)
      break
   end
   lines{end+1} = line;
end

fclose(fIdIn);

% parse the data
if (length(lines) >= 1)

   header = textscan(lines{1}, '%s', 'delimiter', ';');
   header = header{:};
   header = regexprep(header, '-', '_');
   for idF = 1:length(header)
      o_dataStruct.(header{idF}) = nan(1, length(lines)-1);
   end

   colIdToDel = [];
   for idL = 2:length(lines)
      val = textscan(lines{idL}, '%s', 'delimiter', ';');
      val = val{:};
      % if (length(val) ~= length(header))
      %    a=1
      % end
      for idF = 1:length(val)
         valueStr = strtrim(val{idF});
         if (idF > 1)
            if (~isempty(valueStr))
               value = str2double(valueStr);
            else
               value = nan;
            end
            o_dataStruct.(header{idF})(idL-1) = value;
         else
            curDate = valueStr;
            if (length(curDate) == 19)
               curDate = (datenum(curDate, 'dd/mm/yyyy HH:MM:SS')-SHIFT_DATE-EPOCH_OFFSET)*86400;
            elseif (length(curDate) == 23)
               curDate = (datenum(curDate, 'dd/mm/yyyy HH:MM:SS.FFF')-SHIFT_DATE-EPOCH_OFFSET)*86400;
            end
            o_dataStruct.(header{idF})(idL-1) = curDate;
         end
      end
      % if (length(val) ~= length(header))
      %    fprintf('WARNING: Line #%d has not the expected size (%d missing values set to FillValue) in file : %s\n', idL, length(header)-length(val), a_csvFileNameIn);
      % end
   end
end

% remove measurements dated before 01/01/2000
idDel = [];
if (isfield(o_dataStruct, 'Timestamp'))
   idDel = find(o_dataStruct.Timestamp < EPOCH_01_01_2000);
end
if (isfield(o_dataStruct, 'PLD_REALTIMECLOCK'))
   idDel = find(o_dataStruct.PLD_REALTIMECLOCK < EPOCH_01_01_2000);
end
if (~isempty(idDel))
   fields = fieldnames(o_dataStruct);
   for idF = 1:length(fields)
      o_dataStruct.(fields{idF})(idDel) = [];
   end
end

% remove measurements with a time difference > 24 h
idDel = [];
if (isfield(o_dataStruct, 'Timestamp'))
   idCut = find(diff(o_dataStruct.Timestamp) > 86400, 1, 'last');
   idDel = 1:idCut;
end
if (isfield(o_dataStruct, 'PLD_REALTIMECLOCK'))
   idCut = find(diff(o_dataStruct.PLD_REALTIMECLOCK) > 86400, 1, 'last');
   idDel = 1:idCut;
end
if (~isempty(idDel))
   fields = fieldnames(o_dataStruct);
   for idF = 1:length(fields)
      o_dataStruct.(fields{idF})(idDel) = [];
   end
end

end
