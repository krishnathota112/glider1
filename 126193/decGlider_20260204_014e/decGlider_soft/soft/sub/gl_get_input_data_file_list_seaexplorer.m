% ------------------------------------------------------------------------------
% Find and sort seaexplorer input data files according to their names.
%
% SYNTAX :
%  [o_fileNameList, o_fileNumList, o_fileBaseNameList] = ...
%    gl_get_input_data_file_list_seaexplorer(a_dataDirPathName)
%
% INPUT PARAMETERS :
%   a_dataDirPathName : data directory
%
% OUTPUT PARAMETERS :
%   o_fileList         : file information list
%   o_fileNumList      : file number list
%   o_fileBaseNameList : base file name list
%
% EXAMPLES : 
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   08/28/2013 - RNU - creation
% ------------------------------------------------------------------------------
function [o_fileNameList, o_fileNumList, o_fileBaseNameList] = ...
   gl_get_input_data_file_list_seaexplorer(a_dataDirPathName)

o_fileNameList = [];
o_fileNumList = [];
o_fileBaseNameList = [];

% available file names for input data

% CSV files
% SEA029.48.gli.sub.002   
% SEA029.48.gli.sub.003   
% SEA029.48.gli.sub.004   
% SEA029.48.pld1.sub.002  
% SEA029.48.pld1.sub.003  
% SEA029.48.pld1.sub.004  
% or
% sea003.352.gli.sub.1   
% sea003.352.gli.sub.2   
% sea003.352.gli.sub.3   
% sea003.352.pld1.raw.1  
% sea003.352.pld1.raw.2  
% sea003.352.pld1.raw.3

% gz files
% sea027.233.gli.sub.1.gz   
% sea027.233.gli.sub.2.gz   
% sea027.233.gli.sub.3.gz   
% sea027.233.pld1.sub.1.gz  
% sea027.233.pld1.sub.2.gz  
% sea027.233.pld1.sub.3.gz  
% or
% sea002.519.gli.sub.1.gz   
% sea002.519.gli.sub.2.gz   
% sea002.519.gli.sub.3.gz   
% sea002.519.pld1.raw.1.gz  
% sea002.519.pld1.raw.2.gz  
% sea002.519.pld1.raw.3.gz  
% or
% sea010.101.ad2cp.sub.2.gz  % not used yet
% sea010.101.ad2cp.sub.3.gz  % not used yet
% sea010.101.ad2cp.sub.4.gz  % not used yet
% sea010.101.gli.sub.2.gz    
% sea010.101.gli.sub.3.gz    
% sea010.101.gli.sub.4.gz    
% sea010.101.pld1.sub.2.gz   
% sea010.101.pld1.sub.3.gz   
% sea010.101.pld1.sub.4.gz   

fileBaseNameTot = [];
fileNumTot = [];

fileList1 = dir([a_dataDirPathName '*.gli.*.gz']);
fileList2 = dir([a_dataDirPathName '*.pld1.*.gz']);
if (~isempty(fileList1) || ~isempty(fileList2))

   fileInfo = fileList1;
   for idFile = 1:length(fileList1)
      dataInputFile = fileList1(idFile).name;
      dataInputFile = regexprep(dataInputFile, '.gli.sub.', '.gli.');
      idPattern = strfind(dataInputFile, '.gli.');
      fileBaseNameTot{end+1} = dataInputFile(1:idPattern-1);
      fileNumTot(end+1) = str2num(dataInputFile(idPattern+5:end-3));
   end

   fileInfo = [fileInfo; fileList2];
   for idFile = 1:length(fileList2)
      dataInputFile = fileList2(idFile).name;
      dataInputFile = regexprep(dataInputFile, '.pld1.sub.', '.pld1.');
      dataInputFile = regexprep(dataInputFile, '.pld1.raw.', '.pld1.');
      idPattern = strfind(dataInputFile, '.pld1.');
      fileBaseNameTot{end+1} = dataInputFile(1:idPattern-1);
      fileNumTot(end+1) = str2num(dataInputFile(idPattern+6:end-3));
   end

else

   fileList1 = dir([a_dataDirPathName '*.gli.*']);
   fileList2 = dir([a_dataDirPathName '*.pl*.*']);
   if (~isempty(fileList1) || ~isempty(fileList2))

      fileInfo = fileList1;
      for idFile = 1:length(fileList1)
         dataInputFile = fileList1(idFile).name;
         dataInputFile = regexprep(dataInputFile, '.gli.sub.', '.gli.');
         idPattern = strfind(dataInputFile, '.gli.');
         fileBaseNameTot{end+1} = dataInputFile(1:idPattern-1);
         fileNumTot(end+1) = str2num(dataInputFile(idPattern+5:end));
      end

      fileInfo = [fileInfo; fileList2];
      for idFile = 1:length(fileList2)
         dataInputFile = fileList2(idFile).name;
         dataInputFile = regexprep(dataInputFile, '.pld1.sub.', '.pld1.');
         dataInputFile = regexprep(dataInputFile, '.pld1.raw.', '.pld1.');
         idPattern = strfind(dataInputFile, '.pld1.');
         fileBaseNameTot{end+1} = dataInputFile(1:idPattern-1);
         fileNumTot(end+1) = str2num(dataInputFile(idPattern+6:end));
      end
   end
end

% sort the files
[~, idSorted] = sort(fileNumTot);
o_fileNameList = fileInfo(idSorted);
o_fileNumList = fileNumTot(idSorted);
o_fileBaseNameList = fileBaseNameTot(idSorted);

return
