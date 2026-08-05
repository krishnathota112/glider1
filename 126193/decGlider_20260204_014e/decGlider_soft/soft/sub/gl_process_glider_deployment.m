% ------------------------------------------------------------------------------
% Process a glider deployment stored in a directory.
% This directory must contain:
%    - the json deployment file
%    - the data:
%       .bpo files stored in a 'bpo' sub-directory for a seaglider
%       .eng and .log files stored in a 'eng' sub-directory for a seaglider
%       .m and .dat files stored in a 'dat' sub-directory for a slocum
%       .gz files stored in a 'gz' sub-directory for a seaexplorer
%
% SYNTAX :
%  gl_process_glider_deployment(a_deploymentDirName, a_deploymentName, ...
%    a_computeCurrents, a_generateProfiles, a_applyRtqc, a_generateOgFile)
%
% INPUT PARAMETERS :
%   a_deploymentDirName : path name of the deployment directory
%   a_deploymentName    : name of the deployment
%   a_computeCurrents   : compute subsurface currents from slocum glider data
%   a_generateProfiles  : generate profile files from output EGO file data
%   a_applyRtqc         : apply RTQC tests on output EGO file data (and profile
%                         files if generated)
%   a_generateOgFile    : generate OceanGliders file from output EGO file data
%
% OUTPUT PARAMETERS :
%
% EXAMPLES : 
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   08/28/2013 - RNU - creation
% ------------------------------------------------------------------------------
function gl_process_glider_deployment(a_deploymentDirName, a_deploymentName, ...
   a_computeCurrents, a_generateProfiles, a_applyRtqc, a_generateOgFile)

% reference json file of the EGO format
global g_decGl_egoFormatJsonFile;

% type of the glider to process
global g_decGl_gliderType;

% real time processing
global g_decGl_realtimeFlag;

% global configuration values
global g_decGl_oceanGlidersFileOutputDir;

% report information structure
global g_decGl_reportData;
global g_decGl_reportStruct;

% sea Explorer GPS locations
global g_decGl_seaExplorerGpsData;
g_decGl_seaExplorerGpsData = [];

% variable names defined in the json deployment file
global g_decGl_gliderVarName;
global g_decGl_gliderAdjVarName;
global g_decGl_gliderVarPathName;
global g_decGl_egoVarName;

% calibration information defined in the json deployment file
global g_decGl_calibInfo;

% DOXY processing Id defined in the json deployment file
global g_decGl_processingId;

% variable names added to the .mat structure
global g_decGl_directEgoVarPathName;
g_decGl_directEgoVarPathName = [];

% meta-data for derived parameters
global g_decGl_derivedParamMetaData;
g_decGl_derivedParamMetaData = [];

% flag for specific input (NetCDF file of sea glider)
global g_decGl_seaGliderInputNc;
g_decGl_seaGliderInputNc = 0;

% flag for HR data
global g_decGl_hrDataFlag;
g_decGl_hrDataFlag = 0;

% generate CSV report on profile files
global g_decGl_reportOnProfileFlag;

% shallow or deep slocum glider
global g_decGl_shallowSlocumGlider;
g_decGl_shallowSlocumGlider = -1;

% to compute the subsurface current from slocum glider data
COMPUTE_SLOCUM_SUBSURFACE_CURRENT = a_computeCurrents;

% to store the subsurface current estimates in a CSV file
PRINT_CURRENT_ESTIMATES_IN_CSV = 0;


% clean the deployment dir path name
a_deploymentDirName = gl_clean_file_sep_in_path(a_deploymentDirName, 1);

% check input data type
fileExt = '';
if (strcmpi(g_decGl_gliderType, 'seaglider'))
   bpoFile = 0;
   proFile = 0;
   engFile = 0;
   ncFile = 0;
   if (exist([a_deploymentDirName 'bpo' filesep], 'dir') == 7)
      bpoFile = 1;
      fileExt = 'bpo';
      dataDirPathName = [a_deploymentDirName 'bpo' filesep];
   elseif (exist([a_deploymentDirName 'pro' filesep], 'dir') == 7)
      proFile = 1;
      fileExt = 'pro';
      dataDirPathName = [a_deploymentDirName 'pro' filesep];
   elseif (exist([a_deploymentDirName 'eng' filesep], 'dir') == 7)
      engFile = 1;
      fileExt = 'eng';
      dataDirPathName = [a_deploymentDirName 'eng' filesep];
   elseif (exist([a_deploymentDirName 'nc_sg' filesep], 'dir') == 7)
      ncFile = 1;
      fileExt = 'nc';
      g_decGl_seaGliderInputNc = 1;
      dataDirPathName = [a_deploymentDirName 'nc_sg' filesep];
   else
      if (bpoFile+proFile+engFile+ncFile == 0)
         fprintf('ERROR: expecting a ''bpo'' or ''pro'' or ''eng'' or ''nc_sg'' sub-directory of %s => deployment ignored\n', ...
            a_deploymentDirName);
      end
      return
   end
elseif (strcmpi(g_decGl_gliderType, 'slocum'))
   dataDirPathName = [a_deploymentDirName 'dat' filesep];
elseif (strcmpi(g_decGl_gliderType, 'seaexplorer'))
   gzFile = 0;
   csvFile = 0;
   if (exist([a_deploymentDirName 'gz' filesep], 'dir') == 7)
      gzFile = 1;
      dataDirPathName = [a_deploymentDirName 'gz' filesep];
   elseif (exist([a_deploymentDirName 'csv' filesep], 'dir') == 7)
      csvFile = 1;
      dataDirPathName = [a_deploymentDirName 'csv' filesep];
   else
      if (gzFile+csvFile == 0)
         fprintf('ERROR: expecting a ''gz'' or ''csv_raw_HR'' or ''csv'' sub-directory of %s => deployment ignored\n', ...
            a_deploymentDirName);
      end
      return
   end
end

% check if a 'json' directory exists in the deployment directory
expJsonDirName = [a_deploymentDirName 'json' filesep];
if (exist(expJsonDirName, 'dir') == 7)
   
   % a 'json' directory exists in the deployment directory
   % we will create the json deployment file from this directory contents
   fprintf('INFO: a ''json'' directory exist in the deployment directory, we use these stored json files to generate the json file of the deployment\n');

   % check that the json file of the EGO format exists
   if ~(exist(g_decGl_egoFormatJsonFile, 'file') == 2)
      fprintf('ERROR: expected json EGO file not found (%s) => deployment ignored\n', ...
         g_decGl_egoFormatJsonFile);
      return
   end
   
   % check that the deployment json file exists
   sep = strfind(a_deploymentDirName, filesep);
   dirName = a_deploymentDirName(sep(end-1)+1:sep(end)-1);
   jsonInputPathFile = [a_deploymentDirName 'json' filesep dirName '.json'];
   if ~(exist(jsonInputPathFile, 'file') == 2)
      fprintf('ERROR: expected json deployment file not found (%s) => deployment ignored\n', ...
         jsonInputPathFile);
      return
   end
   
   % create the json file for the deployment (from 'json' directory contents)
   deploymentFileName = gl_create_json_deployment_file( ...
      a_deploymentDirName, g_decGl_egoFormatJsonFile, dataDirPathName);
   if (isempty(deploymentFileName))
      return
   end
   fprintf('INFO: json deployment file created: %s\n', ...
      deploymentFileName);
end

% name of the json deployment file
sep = strfind(a_deploymentDirName, filesep);
deploymentName = a_deploymentDirName(sep(end-1)+1:sep(end)-1);
jsonInputPathFile = [a_deploymentDirName 'deployment_' deploymentName '.json'];
if ~(~exist(jsonInputPathFile, 'dir') && exist(jsonInputPathFile, 'file'))
   fprintf('ERROR: expected json deployment file not found (%s) => deployment ignored\n', ...
      jsonInputPathFile);
   return
end

% set g_decGl_hrDataFlag flag
if (strcmp(deploymentName(end-1:end), '_P'))
   g_decGl_hrDataFlag = 1;
   fprintf('INFO: data processed as ''P'' (provisional data)\n');
end

% load the json deployment file
jsonDeployData = gl_load_json(jsonInputPathFile);

% retrieve the glider var 2 EGO var mapping from the json deployment file
% and collect calibration data
[g_decGl_gliderVarName, g_decGl_gliderAdjVarName, g_decGl_gliderVarPathName, ...
   g_decGl_egoVarName, g_decGl_calibInfo, g_decGl_processingId] = ...
   gl_get_var_names_from_json(jsonDeployData);

if (g_decGl_realtimeFlag == 1)
   % initialize data structure to store report information
   g_decGl_reportStruct = gl_get_report_init_struct(jsonInputPathFile);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% process the deployment data
if (exist(dataDirPathName, 'dir'))
   
   fprintf('INFO: processing directory %s\n', dataDirPathName);
   
   ncDirPathName = [a_deploymentDirName 'nc' filesep];
   if (exist(ncDirPathName, 'dir'))
      fprintf('INFO: removing directory %s\n', ncDirPathName);
      rmdir(ncDirPathName, 's')
   end
   mkdir(ncDirPathName);
   tmpDirPathName = [a_deploymentDirName 'tmp' filesep];
   if (exist(tmpDirPathName, 'dir'))
      fprintf('INFO: removing directory %s\n', tmpDirPathName);
      rmdir(tmpDirPathName, 's')
   end
   mkdir(tmpDirPathName);
   profDirPathName = [a_deploymentDirName 'profiles' filesep];
   if (exist(profDirPathName, 'dir'))
      fprintf('INFO: removing directory %s\n', profDirPathName);
      rmdir(profDirPathName, 's')
   end
   mkdir(profDirPathName);
   
   if (g_decGl_hrDataFlag)
      ncOutputPathFile = [a_deploymentDirName  deploymentName '.nc'];
      if (~exist(ncOutputPathFile, 'dir') && exist(ncOutputPathFile, 'file'))
         fprintf('INFO: deleting file %s\n', ncOutputPathFile);
         delete(ncOutputPathFile);
         if (~exist(ncOutputPathFile, 'dir') && exist(ncOutputPathFile, 'file'))
            fprintf('ERROR: cannot delete file %s\n', ncOutputPathFile);
            return
         end
      end
   else
      ncOutputPathFile = [a_deploymentDirName  deploymentName '_R.nc'];
      if (~exist(ncOutputPathFile, 'dir') && exist(ncOutputPathFile, 'file'))
         fprintf('INFO: deleting file %s\n', ncOutputPathFile);
         delete(ncOutputPathFile);
         if (~exist(ncOutputPathFile, 'dir') && exist(ncOutputPathFile, 'file'))
            fprintf('ERROR: cannot delete file %s\n', ncOutputPathFile);
            return
         end
      end
   end

   fprintf('\n');
   
   % GLIDER PROCESSING

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % SLOCUM

   slocumCurrent = [];

   if (strcmpi(g_decGl_gliderType, 'slocum'))

      [vectorFileNameList, sensorFileNameList] = gl_get_input_data_file_list_slocum(dataDirPathName);
      
      % one .sbd.dat or (.sbd.dat, .tbd.dat) or (.mbd.dat, .nbd.dat) file => one
      % raw data structure
      rawDataStructList = [];
      for idF = 1:length(vectorFileNameList)
         vectorDataInputFile = '';
         if (isstruct(vectorFileNameList(idF)))
            if (~isempty(vectorFileNameList(idF)))
               vectorDataInputFile = vectorFileNameList(idF).name;
            end
         else
            if (~isempty(vectorFileNameList{idF}))
               vectorDataInputFile = vectorFileNameList{idF}.name;
            end
         end

         if (isempty(vectorDataInputFile))
            fprintf('WARNING: Sensor file %s cannot be processed (no associated vector file)\n', ...
               sensorFileNameList{idF}.name);
            continue
         end

         vectorDataInputPathFile = [dataDirPathName vectorDataInputFile];
         if (exist(vectorDataInputPathFile, 'file') == 2)

            sensorDataInputPathFile = [];
            if (isempty(sensorFileNameList))

               fprintf('%03d/%03d Processing file ''%s''\n', ...
                  idF, length(vectorFileNameList), ...
                  vectorDataInputFile);

               if (g_decGl_realtimeFlag == 1)
                  % store information for the XML report
                  g_decGl_reportStruct.inputFiles = [g_decGl_reportStruct.inputFiles ...
                     {vectorDataInputPathFile}];
               end

               % check that associated .dat file exists
               [pathstr, fileName, ~] = fileparts(vectorDataInputPathFile);
               vectorDatInputPathFile = [pathstr filesep fileName '.dat'];
               if ~(exist(vectorDatInputPathFile, 'file') == 2)
                  fprintf('WARNING: Associated .dat file not found for file: %s\n', ...
                     vectorDataInputFile);
                  continue
               end

            else

               if (isempty(sensorFileNameList{idF}))

                  fprintf('%03d/%03d Processing file ''%s''\n', ...
                     idF, length(vectorFileNameList), ...
                     vectorDataInputFile);

                  if (g_decGl_realtimeFlag == 1)
                     % store information for the XML report
                     g_decGl_reportStruct.inputFiles = [g_decGl_reportStruct.inputFiles ...
                        {vectorDataInputPathFile}];
                  end
                  
               else

                  sensorDataInputFile = sensorFileNameList{idF}.name;
                  sensorDataInputPathFile = [dataDirPathName sensorDataInputFile];

                  fprintf('%03d/%03d Processing files ''%s'' and ''%s''\n', ...
                     idF, length(vectorFileNameList), ...
                     vectorDataInputFile, ...
                     sensorDataInputFile);

                  if (g_decGl_realtimeFlag == 1)
                     % store information for the XML report
                     g_decGl_reportStruct.inputFiles = [g_decGl_reportStruct.inputFiles ...
                        {vectorDataInputPathFile}];
                     g_decGl_reportStruct.inputFiles = [g_decGl_reportStruct.inputFiles ...
                        {sensorDataInputPathFile}];
                  end

                  % check that associated .dat file exists
                  [pathstr, fileName, ~] = fileparts(vectorDataInputPathFile);
                  vectorDatInputPathFile = [pathstr filesep fileName '.dat'];
                  if ~(exist(vectorDatInputPathFile, 'file') == 2)
                     fprintf('WARNING: Associated .dat file not found for file: %s\n', ...
                        vectorDataInputFile);
                     continue
                  end
                  [pathstr, fileName, ~] = fileparts(sensorDataInputPathFile);
                  sensorDatInputPathFile = [pathstr filesep fileName '.dat'];
                  if ~(exist(sensorDatInputPathFile, 'file') == 2)
                     fprintf('WARNING: Associated .dat file not found for file: %s\n', ...
                        sensorDataInputFile);
                     continue
                  end
               end
               
            end

            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % read the data file(s) and store the Matlab resulting structure in
            % a .mat file
            rawDataStruct = gl_decode_slocum_dat( ...
               vectorDataInputPathFile, sensorDataInputPathFile, COMPUTE_SLOCUM_SUBSURFACE_CURRENT);
            if (~isempty(rawDataStruct))
               rawDataStructList{end+1} = rawDataStruct;
            end
         end
      end

      % depending on shallow or deep slocum glider, we must update
      % TECH_ballast_pumped1 and TECH_ballast_pumped2 technical label from
      % input JSON deployment file
      if (any(strcmp('TECH_ballast_pumped1', g_decGl_egoVarName)))
         jsonDeployData = gl_update_slocum_tech_labels(jsonDeployData);
      end

      fprintf('\nMerge individual Yo data\n');
      rawDataStruct = gl_merge_mat_files_slocum(rawDataStructList);

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % compute subsurface current estimates from slocum data
      if (COMPUTE_SLOCUM_SUBSURFACE_CURRENT)

         fprintf('\nComputing estimates of subsurface current\n');

         % name of the .csv file to store subsurface current data
         csvFilePathName = '';
         if (PRINT_CURRENT_ESTIMATES_IN_CSV)
            csvFilePathName = [ncOutputPathFile(1:end-4) 'current.csv'];
         end

         % compute the subsurface currents
         slocumCurrent = gl_compute_subsurface_current(rawDataStruct, csvFilePathName);
      end

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % SEAGLIDER

   elseif (strcmpi(g_decGl_gliderType, 'seaglider'))

      [fileNameList, fileNumList] = gl_get_input_data_file_list_seaglider(dataDirPathName, fileExt);

      % one .bpo or .pro or .eng or .nc or .dat file => one .mat file
      rawDataStructList = [];
      for idF = 1:length(fileNameList)
         dataInputFile = fileNameList(idF).name;
         dataInputPathFile = [dataDirPathName dataInputFile];
         if (exist(dataInputPathFile, 'file') == 2)

            [pathstr, fileName, ext] = fileparts(dataInputPathFile);
            fprintf('%03d/%03d Processing file %s\n', ...
               idF, length(fileNameList), [fileName ext]);

            if (g_decGl_realtimeFlag == 1)
               % store information for the XML report
               g_decGl_reportStruct.inputFiles = [g_decGl_reportStruct.inputFiles ...
                  {dataInputPathFile}];
            end

            if (engFile == 1)
               % check that associated .log and ppca.eng and/or ppcb.eng file exists
               datInputPathFile = [pathstr filesep fileName '.log'];
               if ~(exist(datInputPathFile, 'file') == 2)
                  fprintf('WARNING: Associated .log file not found for file: %s\n', ...
                     dataInputPathFile);
                  continue
               end
               ppca = 0;
               ppcb = 0;
               datInputPathFile = [pathstr filesep 'ppc' num2str(fileNumList(idF)) 'a.eng'];
               if (exist(datInputPathFile, 'file') == 2)
                  ppca = 1;
               end
               datInputPathFile = [pathstr filesep 'ppc' num2str(fileNumList(idF)) 'b.eng'];
               if (exist(datInputPathFile, 'file') == 2)
                  ppcb = 1;
               end
               if (ppca+ppcb == 0)
                  fprintf('WARNING: At least one associated ppca.eng or ppcb.eng file should be present for file: %s\n', ...
                     dataInputPathFile);
                  continue
               end
            end

            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % read the data file and store the Matlab resulting structure in
            % a .mat file
            rawDataStruct = [];
            if (bpoFile == 1)
               rawDataStruct = gl_decode_seaglider_bpo(dataInputPathFile);
            elseif (proFile == 1)
               rawDataStruct = gl_decode_seaglider_pro(dataInputPathFile);
            elseif (engFile == 1)
               rawDataStruct = gl_decode_seaglider_eng(dataInputPathFile);
            elseif (ncFile == 1)
               rawDataStruct = gl_decode_seaglider_nc(dataInputPathFile);
            end
            if (~isempty(rawDataStruct))
               rawDataStructList{end+1} = rawDataStruct;
            end
         end
      end

      fprintf('\nMerge individual Yo data\n');
      rawDataStruct = gl_merge_mat_files_seaglider(rawDataStructList);

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % SEAEXPLORER
      
   elseif (strcmpi(g_decGl_gliderType, 'seaexplorer'))

      if (gzFile == 1)
         fprintf('\nReading .gz files to generate .mat files\n');
      elseif (csvFile == 1)
         fprintf('\nReading CSV files to generate .mat files\n');
      end

      [fileNameList, fileNumList, fileBaseNameList] = gl_get_input_data_file_list_seaexplorer(dataDirPathName);
      
      % two input files (gli and pl1) => one .mat file
      rawDataStructList = [];
      uFileBaseNameList = unique(fileBaseNameList);
      for fileBase = 1:length(uFileBaseNameList)
         fileBaseName = uFileBaseNameList{fileBase};
         idFiles = find(strcmp(fileBaseNameList, fileBaseName));
         fileNameListForBase = fileNameList(idFiles);
         fileNumListForBase = fileNumList(idFiles);
         uFileNumList = unique(fileNumListForBase);
         for fileNum = 1:length(uFileNumList)
            files = fileNameListForBase(fileNumListForBase == uFileNumList(fileNum));
            rawDataStruct = [];
            for idF = 1:length(files)
               dataInputFile = files(idF).name;
               dataInputPathFile = [dataDirPathName dataInputFile];
               if (~exist(dataInputPathFile, 'dir') && exist(dataInputPathFile, 'file'))

                  [~, fileName, ext] = fileparts(dataInputPathFile);
                  fprintf('%03d/%03d Processing file %s\n', ...
                     fileNum, length(uFileNumList), [fileName ext]);

                  if (g_decGl_realtimeFlag == 1)
                     % store information for the XML report
                     g_decGl_reportStruct.inputFiles = [g_decGl_reportStruct.inputFiles ...
                        {dataInputPathFile}];
                  end

                  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                  % read the data files and store the Matlab resulting structure in
                  % a .mat file
                  rawDataStruct = gl_decode_seaexplorer( ...
                     dataInputPathFile, gzFile, (idF == length(files)), rawDataStruct);
                  if (idF == length(files))
                     if (~isempty(rawDataStruct))
                        rawDataStructList{end+1} = rawDataStruct;
                     end
                  end
               end
            end
         end
      end

      fprintf('\nMerge individual Yo data\n');
      rawDataStruct = gl_merge_mat_files_seaexplorer(rawDataStructList);

   end
   
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % write the EGO NetCDF file from the .mat file

   fprintf('\nProcessing data to generate EGO .nc file\n');

   ok = gl_generate_ego_file(jsonDeployData, rawDataStruct, slocumCurrent, ncOutputPathFile, a_applyRtqc);
   if (~ok)
      return
   end

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % set PHASE and PHASE_NUMBER parameters in the EGO NetCDF file
   gl_set_phase(ncOutputPathFile);
      
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % apply RTQC tests on output EGO file data
   testDoneList = [];
   testFailedList = [];
   if (a_applyRtqc == 1)
      
      fprintf('\nApplying RTQC tests to EGO file data\n');
      
      [testDoneList, testFailedList] = gl_add_rtqc_to_ego_file(ncOutputPathFile, 1);
   end
   
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % interpolate measurement locations of the final EGO file
   gl_update_meas_loc(ncOutputPathFile, a_applyRtqc);

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % generate the Argo profiles from EGO NetCDF file contents according to
   % PHASE and PHASE_NUMBER parameters
   if (a_generateProfiles == 1)
      
      fprintf('\nGenerating NetCDF Argo profile files from EGO NetCDF file\n');
      
      [generatedFileList] = gl_generate_prof(ncOutputPathFile, profDirPathName, ...
         a_applyRtqc, testDoneList, testFailedList);

      if (g_decGl_reportOnProfileFlag)

         % create CSV file to report profile characteristics
         outFilePathName = [ncOutputPathFile(1:end-3) '_PROF_INFO.csv'];

         fidOut = fopen(outFilePathName, 'wt');
         if (fidOut == -1)
            fprintf('ERROR: Unable to create output file: %s\n', outFilePathName);
            return
         end

         DELTA_TIME = 1/24;

         fprintf(fidOut, '#;Name;Dir;Date;N_LEVELS;PRES(1);PRES(end);TIME(1);TIME(end);ANOMALY\n');
         for idF = 1:size(generatedFileList, 1)
            fprintf(fidOut, '%d;%s;%c;%s;%d;%.3f;%.3f;%s;%s', ...
               idF, generatedFileList{idF, 2}, ...
               generatedFileList{idF, 3}, ...
               gl_julian_2_gregorian(generatedFileList{idF, 4}), ...
               generatedFileList{idF, 5:7}, ...
               gl_julian_2_gregorian(generatedFileList{idF, 8}), ...
               gl_julian_2_gregorian(generatedFileList{idF, 9}) ...
               );
            if (idF > 1)
               if ((generatedFileList{idF, 3} == generatedFileList{idF-1, 3}) && ...
                     abs(generatedFileList{idF, 8} - generatedFileList{idF-1, 9}) <= DELTA_TIME)
                  fprintf(fidOut, ';Y\n');
               else
                  fprintf(fidOut, '\n');
               end
            else
               fprintf(fidOut, '\n');
            end
         end
         fclose(fidOut);
      end
      
      % apply RTQC tests on output profile files data
      if (a_applyRtqc == 1)
         
         fprintf('\nApplying RTQC tests to profile files data\n');
         
         for idF = 1:size(generatedFileList, 1)
            gl_add_rtqc_to_profile_file(generatedFileList{idF, 1});
         end
      end
   end
   
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % generate the OceanGliders NetCDF file from EGO NetCDF file contents
   if (a_generateOgFile == 1)
      
      fprintf('\nGenerating NetCDF OceanGliders file from EGO NetCDF file\n');

      outputDirName = [g_decGl_oceanGlidersFileOutputDir '/' a_deploymentName];
      if ~(exist(outputDirName, 'dir'))
         mkdir(outputDirName);
      end
      nc_ego_2_ocean_gliders_file(a_deploymentName, a_deploymentDirName, outputDirName);
   end

   fprintf('... done\n');

   % remove temporary directories
   if (exist(ncDirPathName, 'dir'))
      fprintf('INFO: removing directory %s\n', ncDirPathName);
      rmdir(ncDirPathName, 's')
   end
   if (exist(tmpDirPathName, 'dir'))
      fprintf('INFO: removing directory %s\n', tmpDirPathName);
      rmdir(tmpDirPathName, 's')
   end
   
else
   fprintf('WARNING: cannot find expected data directory (%s) => deployment not processed\n', ...
      dataDirPathName);
end

% store the information for the XML report
if (g_decGl_realtimeFlag == 1)
   g_decGl_reportData = [g_decGl_reportData g_decGl_reportStruct];
end
   
return
