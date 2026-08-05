% ------------------------------------------------------------------------------
% Plot Glider immersions and vertical speeds.
%
% SYNTAX :
%   gl_trace_imm_vs_time
%
% INPUT PARAMETERS :
%   varargin : input arguments
%      must be provided in pairs i.e. ('argument_name', 'argument_value')
%      expected argument names:
%      'data' : identify the deployment (i.e. the sub-directory of the
%               DIR_INPUT_NC_FILES directory) to process
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   22/01/2013 - RNU - creation
% ------------------------------------------------------------------------------
function gl_trace_imm_vs_time(varargin)

global g_GLIDER_BASE_DIR;
global g_GLIDER_DATA_DIR_LIST_GTIVT;
global g_gliderDirNumber_GTIVT;
global g_FIG_GLIDER_PRES_HANDLE;

global g_plotPhase2_GTIVT;
global g_setInSequence_GTIVT;
global g_daysInSet_GTIVT;
global g_all_GTIVT;


% default values initialization
gl_init_default_values;

fprintf('Available commands:\n');
fprintf('   h                : write help and current configuration\n');
fprintf('   Left/Right arrow : previous/next directory\n');
fprintf('   Up/Down arrow    : previous/next EGO NetCDF file\n');
fprintf('   p                : plot/unplot PHASE2\n');
fprintf('   Escape           : exit\n');

DIR_INPUT_NC_FILES = 'C:\Users\jprannou\_DATA\GLIDER\FORMAT_1.5\';
% DIR_INPUT_NC_FILES = 'D:\GLIDER\Collecte_data_glider_20230724\data_ori\slocum';
% DIR_INPUT_NC_FILES = 'C:\Users\jprannou\_DATA\GLIDER\seaglider';
% DIR_INPUT_NC_FILES = 'C:\Users\jprannou\_DATA\GLIDER\seaexplorer';

if (~exist(DIR_INPUT_NC_FILES, 'dir'))
   fprintf('Répertoire inexistant: %s => stop!\n', DIR_INPUT_NC_FILES);
   return
end

g_GLIDER_BASE_DIR = DIR_INPUT_NC_FILES;
g_GLIDER_DATA_DIR_LIST_GTIVT = [];
if (nargin == 0)

   % sub-directories of the base directory
   dirInfo = dir(DIR_INPUT_NC_FILES);
   for dirNum = 1:length(dirInfo)
      if ~(strcmp(dirInfo(dirNum).name, '.') || strcmp(dirInfo(dirNum).name, '..'))
         g_GLIDER_DATA_DIR_LIST_GTIVT{end + 1} = dirInfo(dirNum).name;
      end
   end
else

   for id = 1:2:nargin
      if (strcmpi(varargin{id}, 'data'))
         if (exist([DIR_INPUT_NC_FILES '/' varargin{id+1}], 'dir'))
            g_GLIDER_DATA_DIR_LIST_GTIVT{end + 1} = varargin{id+1};
         else
            fprintf('WARNING: %s is not an existing directory => ignored\n', varargin{id+1});
         end
      else
         fprintf('WARNING: unexpected input argument (%s) => ignored\n', varargin{id});
      end
   end
end

if (isempty(g_GLIDER_DATA_DIR_LIST_GTIVT))
   fprintf('Input Glider directory list => stop!\n');
   return
end

fprintf('Top directory: %s\n', g_GLIDER_BASE_DIR);

% to load first EGO file
g_gliderDirNumber_GTIVT = -1;

g_plotPhase2_GTIVT = 0;

% number of set per sequence
g_setInSequence_GTIVT = 3;

% number of days per set
g_daysInSet_GTIVT = 1;

% plot all data
g_all_GTIVT = 1;

close(findobj('Name', 'Glider immersion vs time'));
warning off;

% figure creation
screenSize = get(0, 'ScreenSize');

g_FIG_GLIDER_PRES_HANDLE = figure('KeyPressFcn', @change_plot, ...
   'Name', 'Glider immersion vs time', ...
   'Position', [1 screenSize(4)*(1/3) screenSize(3) screenSize(4)*(2/3)-90]);

% assign a callback to manage zoom actions
zoomMode = zoom(g_FIG_GLIDER_PRES_HANDLE);
set(zoomMode, 'ActionPostCallback', @after_zoom);

% assign a callback to manage data cursor label
dataCursor = datacursormode(g_FIG_GLIDER_PRES_HANDLE);
set(dataCursor, 'UpdateFcn', @update_cursor_label);

% plot first EGO file
trace_imm_vs_time(0);

return

% ------------------------------------------------------------------------------
% Plot Glider immersions and vertical speeds.
%
% SYNTAX :
%   trace_imm_vs_time(a_gliderDirNumber)
%
% INPUT PARAMETERS :
%   a_gliderDirNumber : number of the directory of the Glider to plot
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   22/01/2013 - RNU - creation
% ------------------------------------------------------------------------------
function trace_imm_vs_time(a_gliderDirNumber)

global g_GLIDER_BASE_DIR;
global g_GLIDER_DATA_DIR_LIST_GTIVT;
global g_GLIDER_DATA_FILE_GTIVT;

global g_gliderDirNumber_GTIVT;
global g_plotPhase2_GTIVT;

global g_FIG_GLIDER_PRES_HANDLE;

global g_time_GTIVT;
global g_pres_GTIVT;
global g_phase_GTIVT;
global g_phase2_GTIVT;
global g_timeVel_GTIVT;
global g_presVel_GTIVT;
global g_phaseVel_GTIVT;
global g_phase2Vel_GTIVT;

global g_presAxes_GTIVT;
global g_velAxes_GTIVT;

global g_minTime_GTIVT;
global g_maxTime_GTIVT;
global g_dataSpan_GTIVT;
global g_setInSequence_GTIVT;
global g_daysInSet_GTIVT;
global g_all_GTIVT;
global g_sequenceNumber_GTIVT;
global g_nbSequence_GTIVT;

global g_decGl_phaseDefault;


figure(g_FIG_GLIDER_PRES_HANDLE);
clf;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% load EGO data
if (a_gliderDirNumber ~= g_gliderDirNumber_GTIVT)

   g_gliderDirNumber_GTIVT = a_gliderDirNumber;

   % directory to consider
   gliderDirName = [g_GLIDER_BASE_DIR '/' g_GLIDER_DATA_DIR_LIST_GTIVT{a_gliderDirNumber+1}];

   fprintf('Considering directory: (%d/%d) %s\n', ...
      a_gliderDirNumber+1, length(g_GLIDER_DATA_DIR_LIST_GTIVT), gliderDirName);

   % EGO files of the directory
   files = dir([gliderDirName '/' g_GLIDER_DATA_DIR_LIST_GTIVT{a_gliderDirNumber+1} '*.nc']);
   if (length(files) ~= 1)
      if (isempty(files))
         fprintf('WARNING: No EGO file in directory : %s\n', gliderDirName);
         return
      else
         fprintf('WARNING: Multiple EGO files in directory : %s\n', gliderDirName);
      end
   end
   fileName = files(1).name;
   filePathName = [gliderDirName '/' fileName];
   g_GLIDER_DATA_FILE_GTIVT = fileName;

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

   g_time_GTIVT = [];
   g_pres_GTIVT = [];
   g_phase_GTIVT = [];
   g_phase2_GTIVT = [];

   g_timeVel_GTIVT = [];
   g_presVel_GTIVT = [];
   g_phaseVel_GTIVT = [];
   g_phase2Vel_GTIVT = [];

   fprintf('   loading file %s start\n', fileName);

   % open NetCDF file
   fCdf = netcdf.open(filePathName, 'NC_WRITE');
   if (isempty(fCdf))
      fprintf('ERROR: Unable to open NetCDF input file: %s\n', filePathName);
      return
   end

   % retrieve immersion data
   immVarId = [];
   if (gl_var_is_present(fCdf, 'PRES'))
      g_pres_GTIVT = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'PRES'));
      fillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, 'PRES'), '_FillValue');
      g_pres_GTIVT(g_pres_GTIVT == fillVal) = nan;
      immVarId = netcdf.inqVarID(fCdf, 'PRES');
   elseif (gl_var_is_present(fCdf, 'DEPTH'))
      g_pres_GTIVT = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'DEPTH'));
      fillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, 'DEPTH'), '_FillValue');
      g_pres_GTIVT(g_pres_GTIVT == fillVal) = nan;
      immVarId = netcdf.inqVarID(fCdf, 'DEPTH');
   else
      fprintf('ERROR: Variable %s (nor %s) not present in file : %s\n', ...
         'PRES', 'DEPTH', fileName);
      netcdf.close(fCdf);
      return
   end

   % retrieve time data
   [varname, xtype, immDimId, natts] = netcdf.inqVar(fCdf, immVarId);
   if (size(immDimId, 2) ~= 1)
      fprintf('ERROR: Inconcistent dimension for immersion variable in file : %s\n', ...
         fileName);
      netcdf.close(fCdf);
      return
   end
   [timeVar, dimlen] = netcdf.inqDim(fCdf, immDimId);
   if (gl_var_is_present(fCdf, timeVar))
      g_time_GTIVT = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, timeVar));
   else
      fprintf('ERROR: Variable %s not present in file : %s\n', ...
         timeVar, fileName);
      netcdf.close(fCdf);
      return
   end

   % retrieve phase data
   if (gl_var_is_present(fCdf, 'PHASE'))
      g_phase_GTIVT = double(netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'PHASE')));
   else
      fprintf('ERROR: Variable %s not present in file : %s\n', ...
         'PHASE', fileName);
      return
   end

   % retrieve phase data
   if (gl_var_is_present(fCdf, 'PHASE2'))
      phase2 = double(netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'PHASE2')));
      if (any(phase2 ~= g_decGl_phaseDefault))
         g_phase2_GTIVT = phase2;
      else
         fprintf('WARNING: Variable %s empty in file : %s\n', ...
            'PHASE2', fileName);
      end
   else
      fprintf('WARNING: Variable %s not present in file : %s\n', ...
         'PHASE2', fileName);
   end

   netcdf.close(fCdf);

   fprintf('   loading file %s done\n', fileName);

   g_timeVel_GTIVT = g_time_GTIVT(2:end);
   g_presVel_GTIVT = diff(g_pres_GTIVT)*100./diff(g_time_GTIVT);
   g_phaseVel_GTIVT = g_phase_GTIVT(2:end);
   g_phase2Vel_GTIVT = g_phase2_GTIVT(2:end);

   g_minTime_GTIVT = min(g_time_GTIVT);
   g_maxTime_GTIVT = max(g_time_GTIVT);
   g_dataSpan_GTIVT = g_maxTime_GTIVT - g_minTime_GTIVT;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% manage plot start/end times
if (g_all_GTIVT == 1)
   timeData = g_time_GTIVT;
   presData = g_pres_GTIVT;
   phaseData = g_phase_GTIVT;
   phase2Data = g_phase2_GTIVT;
   timeVelData = g_timeVel_GTIVT;
   presVelData = g_presVel_GTIVT;
   phaseVelData = g_phaseVel_GTIVT;
   phase2VelData = g_phase2Vel_GTIVT;
else
   startTime = g_minTime_GTIVT + g_sequenceNumber_GTIVT*g_setInSequence_GTIVT*g_daysInSet_GTIVT*86400;
   endTime = g_minTime_GTIVT + (g_sequenceNumber_GTIVT+1)*g_setInSequence_GTIVT*g_daysInSet_GTIVT*86400;

   idStart = find(g_time_GTIVT <= startTime, 1, 'last');
   idEnd = find(g_time_GTIVT >= endTime, 1, 'first');
   if (isempty(idEnd))
      idEnd = length(g_time_GTIVT);
   end
   timeData = g_time_GTIVT(idStart:idEnd);
   presData = g_pres_GTIVT(idStart:idEnd);
   if (all(isnan(presData)))
      fprintf('INFO: No available PRES\n');
   end
   phaseData = g_phase_GTIVT(idStart:idEnd);
   if (~isempty(g_phase2_GTIVT))
      phase2Data = g_phase2_GTIVT(idStart:idEnd);
   else
      phase2Data = [];
   end

   idStart = find(g_timeVel_GTIVT <= startTime, 1, 'last');
   if (isempty(idStart))
      idStart = 1;
   end
   idEnd = find(g_timeVel_GTIVT >= endTime, 1, 'first');
   if (isempty(idEnd))
      idEnd = length(g_timeVel_GTIVT);
   end
   timeVelData = g_timeVel_GTIVT(idStart:idEnd);
   presVelData = g_presVel_GTIVT(idStart:idEnd);
   phaseVelData = g_phaseVel_GTIVT(idStart:idEnd);
   if (~isempty(g_phase2Vel_GTIVT))
      phase2VelData = g_phase2Vel_GTIVT(idStart:idEnd);
   else
      phase2VelData = [];
   end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% plot data

fprintf('   ploting start\n');

% profile on

presAxes = [];
if (~isempty(timeData) && ~isempty(presData))

   presAxes = subplot(2, 1, 1);
   trans = find(diff(phaseData) ~= 0);
   if (~isempty(trans))
      idStart = 1;
      for id = 1:length(trans)+1
         if (id <= length(trans))
            idStop = trans(id);
         else
            idStop = length(timeData);
         end
         xPresT = timeData(idStart:idStop);
         yPresT = presData(idStart:idStop);
         yColorT = phaseData(idStart:idStop);

         plot(presAxes, xPresT, yPresT, 'Color', get_color(yColorT(1)), 'LineStyle', '-', 'Marker', '.');
         hold on;

         idStart = idStop + 1;
      end
   else
      idStart = 1;
      idStop = length(timeData);
      xPresT = timeData(idStart:idStop);
      yPresT = presData(idStart:idStop);
      yColorT = phaseData(idStart:idStop);

      presAxes = subplot(2, 1, 1);
      plot(presAxes, xPresT, yPresT, 'Color', get_color(yColorT(1)), 'LineStyle', '-', 'Marker', '.');
      hold on;
   end

   if ((g_plotPhase2_GTIVT) && (~isempty(phase2Data)))

      uColor2 = unique(phase2Data);
      for idC = 1:length(uColor2)
         idP = find(phase2Data == uColor2(idC));
         xPresT = timeData(idP);
         yPresT = presData(idP);

         scatter(presAxes, xPresT, yPresT, [], get_color(uColor2(idC)), 'Marker', 'o');
         hold on;
      end
   end

   minTime = min(timeData);
   maxTime = max(timeData);

   minPres = min(presData);
   maxPres = max(presData);
end
g_presAxes_GTIVT = presAxes;

velAxes = [];
if (~isempty(timeVelData) && ~isempty(presVelData))

   velAxes = subplot(2, 1, 2);
   trans = find(diff(phaseVelData) ~= 0);
   if (~isempty(trans))
      idStart = 1;
      for id = 1:length(trans)+1
         if (id <= length(trans))
            idStop = trans(id);
         else
            idStop = length(timeVelData);
         end
         xVelT = timeVelData(idStart:idStop);
         yVelT = presVelData(idStart:idStop);
         yColorT = phaseVelData(idStart:idStop);

         plot(velAxes, xVelT, yVelT, 'Color', get_color(yColorT(1)), 'LineStyle', '-', 'Marker', '.');
         hold on;

         idStart = idStop + 1;
      end
   else
      idStart = 1;
      idStop = length(timeVelData);
      xVelT = timeVelData(idStart:idStop);
      yVelT = presVelData(idStart:idStop);
      yColorT = phaseVelData(idStart:idStop);

      plot(velAxes, xVelT, yVelT, 'Color', get_color(yColorT), 'LineStyle', '-', 'Marker', '.');
      hold on;
   end

   if ((g_plotPhase2_GTIVT) && (~isempty(phase2Data)))

      uColor2 = unique(phase2VelData);
      for idC = 1:length(uColor2)
         idP = find(phase2VelData == uColor2(idC));
         xVelT = timeVelData(idP);
         yVelT = presVelData(idP);

         scatter(velAxes, xVelT, yVelT, [], get_color(uColor2(idC)), 'Marker', 'o');
         hold on;
      end
   end

   minVel = min(presVelData);
   maxVel = max(presVelData);
end
g_velAxes_GTIVT = velAxes;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% plot finalization

if (~isempty(presAxes))

   % backward increasing pressures
   set(presAxes, 'YDir', 'reverse');

   % pressure axis boundaries
   minPres = 5*floor(minPres/5);
   if ((minPres == 0) || isnan(minPres))
      minPres = -1;
   end
   maxPres = 5*ceil(maxPres/5);
   if ((maxPres == 0) || isnan(maxPres))
      maxPres = 1;
   end
   set(presAxes, 'Ylim', [minPres maxPres]);

   % axis title
   set(get(presAxes, 'YLabel'), 'String', 'Pressure (dbar)');

   % time axis
   minTime = 600*floor(minTime/600);
   maxTime = 600*ceil(maxTime/600);
   if (minTime == maxTime)
      minTime = minTime - 600;
      maxTime = maxTime + 600;
   end

   set(presAxes, 'Xlim', [minTime maxTime]);

   % time axis tick labels
   deltaTick = round((maxTime - minTime)/10);
   xTick = [];
   for idX = minTime:deltaTick:maxTime
      xTick = [xTick idX];
   end
   set(presAxes, 'XTick', xTick);

   xTick = get(presAxes, 'XTick');
   xTick = epoch2datenum(xTick);
   if (max(xTick) - min(xTick) > 2)
      xTickLabel = datestr(xTick, 'dd/mm/yyyy');
   else
      xTickLabel = datestr(xTick, 'dd/mm/yyyy HH:MM:SS');
   end
   set(presAxes, 'XTickLabel', xTickLabel);
end

if (~isempty(velAxes))

   % velocity axis boundaries
   minVel = floor(minVel);
   if (isnan(minVel) || (minVel == 0))
      minVel = -1;
   end
   maxVel = ceil(maxVel);
   if (isnan(maxVel) || (maxVel == 0))
      maxVel = 1;
   end
   set(velAxes, 'Ylim', [minVel maxVel]);

   % axis title
   set(get(velAxes, 'YLabel'), 'String', 'Vertical speed (cm/s)');

   % time axis
   set(velAxes, 'Xlim', [minTime maxTime]);

   % time axis tick labels
   deltaTick = round((maxTime - minTime)/10);
   xTick = [];
   for idX = minTime:deltaTick:maxTime
      xTick = [xTick idX];
   end
   set(velAxes, 'XTick', xTick);

   xTick = get(velAxes, 'XTick');
   xTick = epoch2datenum(xTick);
   if (max(xTick) - min(xTick) > 2)
      xTickLabel = datestr(xTick, 'dd/mm/yyyy');
   else
      xTickLabel = datestr(xTick, 'dd/mm/yyyy HH:MM:SS');
   end
   set(velAxes, 'XTickLabel', xTickLabel);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% plot title

set(0,'DefaulttextInterpreter','none');
if (~isempty(timeData) && ~isempty(presData))
   label = sprintf('%02d/%02d : glider file %s', ...
      a_gliderDirNumber+1, ...
      length(g_GLIDER_DATA_DIR_LIST_GTIVT), ...
      g_GLIDER_DATA_FILE_GTIVT);
else
   label = sprintf('%02d/%02d : no data in glider file %s', ...
      a_gliderDirNumber+1, ...
      length(g_GLIDER_DATA_DIR_LIST_GTIVT), ...
      g_GLIDER_DATA_FILE_GTIVT);
end
if (g_all_GTIVT == 0)
   label = [label sprintf(' - SEQ(%d/%d)', g_sequenceNumber_GTIVT+1, g_nbSequence_GTIVT)];
end

if ((~isempty(presAxes)) || (~isempty(velAxes)))
   title(presAxes, label, 'FontSize', 14);
else
   title(label, 'FontSize', 14);
end

fprintf('   ploting done\n');

% profile viewer

return

% ------------------------------------------------------------------------------
% Management of 'KeyPressFcn' callback
%
% SYNTAX :
%   change_plot(a_src, a_eventData)
%
% INPUT PARAMETERS :
%   a_src       : focused object when event occurred
%   a_eventData : event information
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   22/01/2013 - RNU - creation
% ------------------------------------------------------------------------------
function change_plot(a_src, a_eventData)

global g_GLIDER_DATA_DIR_LIST_GTIVT;

global g_gliderDirNumber_GTIVT;

global g_plotPhase2_GTIVT;
global g_sequenceNumber_GTIVT;
global g_setInSequence_GTIVT;
global g_daysInSet_GTIVT;
global g_all_GTIVT;
global g_dataSpan_GTIVT;
global g_nbSequence_GTIVT;

global g_FIG_GLIDER_PRES_HANDLE;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% exit
if (strcmp(a_eventData.Key, 'escape'))
   set(g_FIG_GLIDER_PRES_HANDLE, 'KeyPressFcn', '');
   close(g_FIG_GLIDER_PRES_HANDLE);
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % next directory
elseif (strcmp(a_eventData.Key, 'rightarrow'))
   if (length(g_GLIDER_DATA_DIR_LIST_GTIVT) > 1)
      g_all_GTIVT = 1;
      trace_imm_vs_time(mod(g_gliderDirNumber_GTIVT+1, length(g_GLIDER_DATA_DIR_LIST_GTIVT)));
   end
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % previous directory
elseif (strcmp(a_eventData.Key, 'leftarrow'))
   if (length(g_GLIDER_DATA_DIR_LIST_GTIVT) > 1)
      g_all_GTIVT = 1;
      trace_imm_vs_time(mod(g_gliderDirNumber_GTIVT-1, length(g_GLIDER_DATA_DIR_LIST_GTIVT)));
   end
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % previous sequence of data
elseif (strcmp(a_eventData.Key, 'uparrow'))
   if (g_all_GTIVT == 0)
      g_sequenceNumber_GTIVT = mod(g_sequenceNumber_GTIVT-1, g_nbSequence_GTIVT);
   end
   trace_imm_vs_time(g_gliderDirNumber_GTIVT);
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % next sequence of data
elseif (strcmp(a_eventData.Key, 'downarrow'))
   if (g_all_GTIVT == 0)
      g_sequenceNumber_GTIVT = mod(g_sequenceNumber_GTIVT+1, g_nbSequence_GTIVT);
   end
   trace_imm_vs_time(g_gliderDirNumber_GTIVT);
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % switch between all/sequence plot
elseif (strcmp(a_eventData.Key, 'd'))
   if (g_all_GTIVT == 1)
      g_all_GTIVT = 0;
      g_nbSequence_GTIVT = ceil((g_dataSpan_GTIVT/86400)/(g_setInSequence_GTIVT*g_daysInSet_GTIVT));
      g_sequenceNumber_GTIVT = 0;
   else
      g_all_GTIVT = 1;
   end
   trace_imm_vs_time(g_gliderDirNumber_GTIVT);
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % plot/unplot PHASE2
elseif (strcmp(a_eventData.Key, 'p'))
   if (g_plotPhase2_GTIVT == 1)
      g_plotPhase2_GTIVT = 0;
   else
      g_plotPhase2_GTIVT = 1;
   end
   trace_imm_vs_time(g_gliderDirNumber_GTIVT);
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % write help
elseif (strcmp(a_eventData.Key, 'h'))
   fprintf('\n');
   fprintf('Available commands:\n');
   fprintf('   h                : write help and current configuration\n');
   fprintf('   Left/Right arrow : previous/next Glider directory\n');
   fprintf('   Up/Down arrow    : previous/next sequence of data\n');
   fprintf('   d                : switch between all or sequence plots\n');
   fprintf('   p                : plot/unplot PHASE2\n');
   fprintf('   Escape           : exit\n');
   fprintf('\n');
end

return

% ------------------------------------------------------------------------------
% Retrieve color of a given PHASE value.
%
% SYNTAX :
% [o_color] = get_color(a_phaseVal)
%
% INPUT PARAMETERS :
%   a_phaseVal : PHASE value
%
% OUTPUT PARAMETERS :
%   o_color : color of the PHASE
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   22/01/2013 - RNU - creation
% ------------------------------------------------------------------------------
function [o_color] = get_color(a_phaseVal)

% PHASE codes
global g_decGl_phaseSurfDrift;
global g_decGl_phaseDescent;
global g_decGl_phaseSubSurfDrift;
global g_decGl_phaseInflexion;
global g_decGl_phaseAscent;
global g_decGl_phaseInconsistant;
global g_decGl_phaseDefault;

o_color = [];

phaseVal = unique(a_phaseVal);
if (length(phaseVal) ~= 1)
   fprintf('ERROR: many phase values!\n');
   return
end

if (isnan(phaseVal))
   o_color = 'k';
   return
end

switch phaseVal
   case g_decGl_phaseSurfDrift
      o_color = 'g';
   case g_decGl_phaseDescent
      o_color = [102 204 204]/255;
   case g_decGl_phaseSubSurfDrift
      o_color = 'c';
   case g_decGl_phaseInflexion
      o_color = 'b';
   case g_decGl_phaseAscent
      o_color = [255 102 102]/255;
   case g_decGl_phaseInconsistant
      o_color = 'r';
   case g_decGl_phaseDefault
      o_color = 'k';
   otherwise
      fprintf('Undefined color for this phase value!\n');
end

return

% ------------------------------------------------------------------------------
% Management time tick labels after a zoom + update of Xlim of the other plot.
%
% SYNTAX :
%   after_zoom(a_src, a_eventData)
%
% INPUT PARAMETERS :
%   a_src       : focused object when event occurred
%   a_eventData : event information
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   27/08/2019 - RNU - creation
% ------------------------------------------------------------------------------
function after_zoom(a_src, a_eventData)

global g_presAxes_GTIVT;
global g_velAxes_GTIVT;


% update tick labels of the focused plot
xLim = get(a_eventData.Axes, 'XLim');
deltaTick = round((xLim(2) - xLim(1))/10);
xTick = [];
for idX = xLim(1):deltaTick:xLim(2)
   xTick = [xTick idX];
end
set(a_eventData.Axes, 'XTick', xTick);

xTickDay = epoch2datenum(xTick);
if (max(xTickDay) - min(xTickDay) > 5)
   xTickLabel = datestr(xTickDay, 'dd/mm/yyyy');
else
   xTickLabel = datestr(xTickDay, 'dd/mm/yyyy  HH:MM:SS');
end
set(a_eventData.Axes, 'XTickLabel', xTickLabel);

% update 'Xlim' and tick labels of the other plot
otherAxes = [];
if (a_eventData.Axes == g_presAxes_GTIVT)
   otherAxes = g_velAxes_GTIVT;
elseif (a_eventData.Axes == g_velAxes_GTIVT)
   otherAxes = g_presAxes_GTIVT;
end

if (~isempty(otherAxes))
   set(otherAxes, 'Xlim', get(a_eventData.Axes, 'Xlim'));
   set(otherAxes, 'XTick', get(a_eventData.Axes, 'XTick'));
   set(otherAxes, 'XTickLabel', get(a_eventData.Axes, 'XTickLabel'));
end

return

% ------------------------------------------------------------------------------
% Update data cursor label.
%
% SYNTAX :
%  [o_label] = update_cursor_label(a_src, a_eventData)
%
% INPUT PARAMETERS :
%   a_src       : focused object when event occurred
%   a_eventData : event information
%
% OUTPUT PARAMETERS :
%   o_label : new cursor label to display
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   27/08/2019 - RNU - creation
% ------------------------------------------------------------------------------
function [o_label] = update_cursor_label(a_src, a_eventData)

global g_presAxes_GTIVT;
global g_velAxes_GTIVT;

% default values
global g_decGl_janFirst1950InMatlab;


% find parent subplot to set unit to be displayed
if (a_src.Parent == g_presAxes_GTIVT)
   unit = 'dbar';
elseif (a_src.Parent == g_velAxes_GTIVT)
   unit = 'cm/s';
end

% update cursor label
cursorPos = get(a_eventData, 'Position');
xLabel = datestr(gl_epoch_2_julian(cursorPos(1)) + g_decGl_janFirst1950InMatlab, 'dd/mm/yyyy  HH:MM:SS');
yLabel = [num2str(cursorPos(2)) ' ' unit];

o_label = {xLabel, yLabel};

return
