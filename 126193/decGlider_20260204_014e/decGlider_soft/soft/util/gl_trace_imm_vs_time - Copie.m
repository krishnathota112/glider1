% ------------------------------------------------------------------------------
% Tracé des immersions et vitesses verticales de gliders
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

global g_GLIDER_DATA_DIR_LIST_GTIVT;
global g_gliderDirNumber_GTIVT;
global g_plotPhase2_GTIVT
global g_FIG_GLIDER_PRES_HANDLE;


% default values initialization
gl_init_default_values;

fprintf('Available commands:\n');
fprintf('   h                : write help and current configuration\n');
fprintf('   Left/Right arrow : previous/next directory\n');
fprintf('   Up/Down arrow    : previous/next EGO NetCDF file\n');
fprintf('   p                : plot/unplot PHASE2\n');
fprintf('   Escape           : exit\n');

DIR_INPUT_NC_FILES = 'C:\Users\jprannou\_DATA\GLIDER\FORMAT_1.4\';
DIR_INPUT_NC_FILES = 'F:\GLIDER\seaexplorer\';
DIR_INPUT_NC_FILES = 'F:\GLIDER\seaglider\';

if (~exist(DIR_INPUT_NC_FILES, 'dir'))
   fprintf('Répertoire inexistant: %s => stop!\n', DIR_INPUT_NC_FILES);
   return
end

g_GLIDER_DATA_DIR_LIST_GTIVT = [];
if (nargin == 0)

   % le répertoire pris en compte est le répertoire par défaut

   % liste des sous-repertoires de données gliders
   dirInfo = dir(DIR_INPUT_NC_FILES);
   for dirNum = 1:length(dirInfo)
      if ~(strcmp(dirInfo(dirNum).name, '.') || strcmp(dirInfo(dirNum).name, '..'))
         dirPathName = [DIR_INPUT_NC_FILES '/' dirInfo(dirNum).name '/'];
         g_GLIDER_DATA_DIR_LIST_GTIVT{end + 1} = dirPathName;
      end
   end
else

   % le répertoire pris en compte est celui fourni en paramètre

   for id = 1:2:nargin
      if (strcmpi(varargin{id}, 'data'))
         if (exist([DIR_INPUT_NC_FILES '/' varargin{id+1}], 'dir'))
            g_GLIDER_DATA_DIR_LIST_GTIVT{end + 1} = [DIR_INPUT_NC_FILES '/' varargin{id+1} '/'];
         else
            fprintf('WARNING: %s is not an existing directory => ignored\n', varargin{id+1});
         end
      else
         fprintf('WARNING: unexpected input argument (%s) => ignored\n', varargin{id});
      end
   end
end

if (isempty(g_GLIDER_DATA_DIR_LIST_GTIVT))
   fprintf('Liste des répertoires vide => stop!\n');
   return
end

fprintf('Top directory: %s\n', DIR_INPUT_NC_FILES);

% pour forcer le chargement des données du premier glider
g_gliderDirNumber_GTIVT = -1;

g_plotPhase2_GTIVT = 1;

close(findobj('Name', 'Glider immersion vs time'));
warning off;

% création de la figure à laquelle on affecte une callback pour gérer le
% défilement des gliders et des fichiers
screenSize = get(0, 'ScreenSize');

g_FIG_GLIDER_PRES_HANDLE = figure('KeyPressFcn', @change_plot, ...
   'Name', 'Glider immersion vs time', ...
   'Position', [1 screenSize(4)*(1/3) screenSize(3) screenSize(4)*(2/3)-90]);

% assign a callback to manage zoom actions
zoomMode = zoom(g_FIG_GLIDER_PRES_HANDLE);
set(zoomMode, 'ActionPostCallback', @after_zoom);

% on lance le tracé des pressions du premier fichier du premier glider
trace_imm_vs_time(0, 0);

return

% ------------------------------------------------------------------------------
% Tracé des immersions et vitesses verticales de gliders
%
% SYNTAX :
%   trace_imm_vs_time(a_gliderDirNumber, a_gliderFileNumber)
%
% INPUT PARAMETERS :
%   a_gliderDirNumber  : numéro du répertoire du glider à tracer
%   a_gliderFileNumber : numéro du fichier glider à tracer
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
function trace_imm_vs_time(a_gliderDirNumber, a_gliderFileNumber)

global g_GLIDER_DATA_DIR_LIST_GTIVT;
global g_GLIDER_DATA_FILE_LIST_GTIVT;

global g_gliderDirNumber_GTIVT;
global g_gliderFileNumber_GTIVT;
global g_plotPhase2_GTIVT;

global g_FIG_GLIDER_PRES_HANDLE;

global g_time_GTIVT;
global g_pres_GTIVT;
global g_phase_GTIVT;
global g_phase2_GTIVT;
global g_timeVel_GTIVT;
global g_presVel_GTIVT;

global g_presAxes_GTIVT;
global g_velAxes_GTIVT;

global g_decGl_phaseDefault;


% tracé des données demandées
figure(g_FIG_GLIDER_PRES_HANDLE);
clf;

if ((a_gliderDirNumber ~= g_gliderDirNumber_GTIVT) || (a_gliderFileNumber ~= g_gliderFileNumber_GTIVT))

   if (a_gliderDirNumber ~= g_gliderDirNumber_GTIVT)
      % répertoire à prendre en compte
      gliderDirName = char(g_GLIDER_DATA_DIR_LIST_GTIVT(a_gliderDirNumber+1));
      % fichiers netCDF du répertoire
      g_GLIDER_DATA_FILE_LIST_GTIVT = [];
      files = dir([gliderDirName '*.nc']);
      for fileNum = 1:length(files)
         filePathName = [gliderDirName '/' files(fileNum).name];
         if (~exist(filePathName, 'dir') && exist(filePathName, 'file'))
            g_GLIDER_DATA_FILE_LIST_GTIVT{end + 1} = filePathName;
         end
      end

      fprintf('Considering directory: %s (%d files)\n', ...
         char(g_GLIDER_DATA_DIR_LIST_GTIVT(a_gliderDirNumber+1)), ...
         length(g_GLIDER_DATA_FILE_LIST_GTIVT));

      % on repart au premier fichier du répertoire
      a_gliderFileNumber = 0;
   end

   g_gliderDirNumber_GTIVT = a_gliderDirNumber;
   g_gliderFileNumber_GTIVT = a_gliderFileNumber;

   if (isempty(g_GLIDER_DATA_FILE_LIST_GTIVT))
      fprintf('Empty directory: %s\n', char(g_GLIDER_DATA_DIR_LIST_GTIVT(a_gliderDirNumber+1)));
      return
   end

   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % lecture et stockage des données associées à ce fichier de ce glider

   g_time_GTIVT = [];
   g_pres_GTIVT = [];
   g_phase_GTIVT = [];
   g_phase2_GTIVT = [];
   g_timeVel_GTIVT = [];
   g_presVel_GTIVT = [];

   gliderFileName = char(g_GLIDER_DATA_FILE_LIST_GTIVT(a_gliderFileNumber+1));

   [~, filePath, FileExt] = fileparts(gliderFileName);
   fprintf('   loading file %s start\n', [filePath FileExt]);

   % check if the file exists
   if (~exist(gliderFileName, 'file'))
      fprintf('WARNING: File not found : %s\n', gliderFileName);
      return
   end

   % open NetCDF file
   fCdf = netcdf.open(gliderFileName, 'NC_WRITE');
   if (isempty(fCdf))
      fprintf('ERROR: Unable to open NetCDF input file: %s\n', gliderFileName);
      return
   end

   % retrieve immersion data
   immVarId = [];
   if (gl_var_is_present(fCdf, 'PRES'))
      g_pres_GTIVT = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'PRES'));
      fillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, 'PRES'), '_FillValue');
      g_pres_GTIVT(find(g_pres_GTIVT == fillVal)) = nan;
      immVarId = netcdf.inqVarID(fCdf, 'PRES');
   elseif (gl_var_is_present(fCdf, 'DEPTH'))
      g_pres_GTIVT = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'DEPTH'));
      fillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, 'DEPTH'), '_FillValue');
      g_pres_GTIVT(find(g_pres_GTIVT == fillVal)) = nan;
      immVarId = netcdf.inqVarID(fCdf, 'DEPTH');
   else
      fprintf('ERROR: Variable %s (nor %s) not present in file : %s\n', ...
         'PRES', 'DEPTH', gliderFileName);
      netcdf.close(fCdf);
      return
   end

   % retrieve time data
   [varname, xtype, immDimId, natts] = netcdf.inqVar(fCdf, immVarId);
   if (size(immDimId, 2) ~= 1)
      fprintf('ERROR: Inconcistent dimension for immersion variable in file : %s\n', ...
         gliderFileName);
      netcdf.close(fCdf);
      return
   end
   [timeVar, dimlen] = netcdf.inqDim(fCdf, immDimId);
   if (gl_var_is_present(fCdf, timeVar))
      g_time_GTIVT = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, timeVar));
      g_time_GTIVT(find(isnan(g_pres_GTIVT))) = nan;
   else
      fprintf('ERROR: Variable %s not present in file : %s\n', ...
         timeVar, gliderFileName);
      netcdf.close(fCdf);
      return
   end

   % retrieve phase data
   if (gl_var_is_present(fCdf, 'PHASE'))
      g_phase_GTIVT = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'PHASE'));
      g_phase_GTIVT(find(isnan(g_pres_GTIVT))) = nan;
   else
      fprintf('ERROR: Variable %s not present in file : %s\n', ...
         'PHASE', gliderFileName);
      return
   end
   if (gl_var_is_present(fCdf, 'PHASE2'))
      phase2 = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'PHASE2'));
      if (any(phase2 ~= g_decGl_phaseDefault))
         g_phase2_GTIVT = phase2;
         g_phase2_GTIVT(find(isnan(g_pres_GTIVT))) = nan;
      else
         fprintf('WARNING: Variable %s empty in file : %s\n', ...
            'PHASE2', gliderFileName);
      end
   else
      fprintf('WARNING: Variable %s not present in file : %s\n', ...
         'PHASE2', gliderFileName);
   end

   netcdf.close(fCdf);

   g_timeVel_GTIVT = g_time_GTIVT(2:end);
   g_presVel_GTIVT = diff(g_pres_GTIVT)*100./diff(g_time_GTIVT);

   fprintf('   loading file %s done\n', [filePath FileExt]);

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% tracé des données

fprintf('   ploting start\n');

% profile on

presAxes = [];
if (~isempty(g_time_GTIVT) && ~isempty(g_pres_GTIVT))
   yColor = g_phase_GTIVT;

   presAxes = subplot(2, 1, 1);
   trans = find(diff(yColor) ~= 0);
   if (~isempty(trans))
      idStart = 1;
      for id = 1:length(trans)+1
         if (id <= length(trans))
            idStop = trans(id);
         else
            idStop = length(g_time_GTIVT);
         end
         xPresT = g_time_GTIVT(idStart:idStop);
         yPresT = g_pres_GTIVT(idStart:idStop);
         yColorT = yColor(idStart:idStop);

         plot(presAxes, xPresT, yPresT, 'Color', get_color(yColorT(1)), 'LineStyle', '-', 'Marker', '.');
         hold on;

         idStart = idStop + 1;
      end
   else
      idStart = 1;
      idStop = length(g_time_GTIVT);
      xPresT = g_time_GTIVT(idStart:idStop);
      yPresT = g_pres_GTIVT(idStart:idStop);
      yColorT = g_phase_GTIVT(idStart:idStop);

      presAxes = subplot(2, 1, 1);
      plot(presAxes, xPresT, yPresT, 'Color', get_color(yColorT(1)), 'LineStyle', '-', 'Marker', '.');
      hold on;
   end

   if ((g_plotPhase2_GTIVT) && (~isempty(g_phase2_GTIVT)))
      yColor2 = g_phase2_GTIVT;

      uColor2 = unique(yColor2);
      for idC = 1:length(uColor2)
         idP = find(yColor2 == uColor2(idC));
         xPresT = g_time_GTIVT(idP);
         yPresT = g_pres_GTIVT(idP);
         
         scatter(presAxes, xPresT, yPresT, [], get_color(uColor2(idC)), 'Marker', 'o');
         hold on;
      end
   end

   minTime = min(g_time_GTIVT);
   maxTime = max(g_time_GTIVT);

   minPres = min(g_pres_GTIVT);
   maxPres = max(g_pres_GTIVT);
end
g_presAxes_GTIVT = presAxes;

velAxes = [];
if (~isempty(g_timeVel_GTIVT) && ~isempty(g_presVel_GTIVT))
   yColor = g_phase_GTIVT(2:end);

   velAxes = subplot(2, 1, 2);
   trans = find(diff(yColor) ~= 0);
   if (~isempty(trans))
      idStart = 1;
      for id = 1:length(trans)+1
         if (id <= length(trans))
            idStop = trans(id);
         else
            idStop = length(g_timeVel_GTIVT);
         end
         xVelT = g_timeVel_GTIVT(idStart:idStop);
         yVelT = g_presVel_GTIVT(idStart:idStop);
         yColorT = yColor(idStart:idStop);

         plot(velAxes, xVelT, yVelT, 'Color', get_color(yColorT(1)), 'LineStyle', '-', 'Marker', '.');
         hold on;

         idStart = idStop + 1;
      end
   else
      idStart = 1;
      idStop = length(g_timeVel_GTIVT);
      xVelT = g_timeVel_GTIVT(idStart:idStop);
      yVelT = g_presVel_GTIVT(idStart:idStop);
      yColorT = yColor(idStart:idStop);

      plot(velAxes, xVelT, yVelT, 'Color', get_color(yColorT), 'LineStyle', '-', 'Marker', '.');
      hold on;
   end

   if ((g_plotPhase2_GTIVT) && (~isempty(g_phase2_GTIVT)))
      yColor2 = g_phase2_GTIVT(2:end);

      uColor2 = unique(yColor2);
      for idC = 1:length(uColor2)
         idP = find(yColor2 == uColor2(idC));
         xVelT = g_timeVel_GTIVT(idP);
         yVelT = g_presVel_GTIVT(idP);

         scatter(velAxes, xVelT, yVelT, [], get_color(uColor2(idC)), 'Marker', 'o');
         hold on;
      end
   end

   minVel = min(g_presVel_GTIVT);
   maxVel = max(g_presVel_GTIVT);
end
g_velAxes_GTIVT = velAxes;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% finition des tracés

if (~isempty(presAxes))

   % pressions croissantes vers le bas
   set(presAxes, 'YDir', 'reverse');

   % gestion des bornes de l'axe
   minPres = 5*floor(minPres/5);
   if (minPres == 0)
      minPres = -1;
   end
   maxPres = 5*ceil(maxPres/5);
   if (maxPres == 0)
      maxPres = 1;
   end
   set(presAxes, 'Ylim', [minPres maxPres]);

   % titre de l'axe
   set(get(presAxes, 'YLabel'), 'String', 'Pressure (dbar)');

   % axe des abscisses (temps)
   minTime = 600*floor(minTime/600);
   maxTime = 600*ceil(maxTime/600);
   if (minTime == maxTime)
      minTime = minTime - 600;
      maxTime = maxTime + 600;
   end

   set(presAxes, 'Xlim', [minTime maxTime]);

   % gestion des labels de l'axe des abscisses (Dates)
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

   % gestion des bornes de l'axe
   minVel = floor(minVel);
   if (minVel == 0)
      minVel = -1;
   end
   maxVel = ceil(maxVel);
   if (maxVel == 0)
      maxVel = 1;
   end
   set(velAxes, 'Ylim', [minVel maxVel]);

   % titre de l'axe
   set(get(velAxes, 'YLabel'), 'String', 'Vertical speed (cm/s)');

   % axe des abscisses (temps)
   set(velAxes, 'Xlim', [minTime maxTime]);

   % gestion des labels de l'axe des abscisses (Dates)
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
% titre du tracé

set(0,'DefaulttextInterpreter','none');
[pathstr, name, ext] = fileparts(g_GLIDER_DATA_FILE_LIST_GTIVT{a_gliderFileNumber+1}) ;
if (~isempty(g_time_GTIVT) && ~isempty(g_pres_GTIVT))
   label = sprintf('%02d/%02d : glider file %s', ...
      a_gliderFileNumber+1, ...
      length(g_GLIDER_DATA_FILE_LIST_GTIVT), ...
      [name ext]);
else
   label = sprintf('%02d/%02d : no data in glider file %s', ...
      a_gliderFileNumber+1, ...
      length(g_GLIDER_DATA_FILE_LIST_GTIVT), ...
      [name ext]);
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
% Callback de gestion des tracés:
%   - Left/Right arrow : previous/next directory
%   - Up/Down arrow    : previous/next EGO NetCDF file
%   - up/down Arrow : fichier glider précédent/suivant
%   - Escape           : exit
%
% SYNTAX :
%   change_plot(a_src, a_eventData)
%
% INPUT PARAMETERS :
%   a_src        : objet source
%   a_eventData  : évènement déclencheur
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
global g_GLIDER_DATA_FILE_LIST_GTIVT;

global g_gliderDirNumber_GTIVT;
global g_gliderFileNumber_GTIVT;
global g_plotPhase2_GTIVT;

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
      trace_imm_vs_time( ...
         mod(g_gliderDirNumber_GTIVT+1, length(g_GLIDER_DATA_DIR_LIST_GTIVT)), ...
         0);
   end
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % previous directory
elseif (strcmp(a_eventData.Key, 'leftarrow'))
   if (length(g_GLIDER_DATA_DIR_LIST_GTIVT) > 1)
      trace_imm_vs_time( ...
         mod(g_gliderDirNumber_GTIVT-1, length(g_GLIDER_DATA_DIR_LIST_GTIVT)), ...
         0);
   end
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % previous EGO file
elseif (strcmp(a_eventData.Key, 'uparrow'))
   if (length(g_GLIDER_DATA_FILE_LIST_GTIVT) > 1)
      trace_imm_vs_time( ...
         g_gliderDirNumber_GTIVT, ...
         mod(g_gliderFileNumber_GTIVT-1, length(g_GLIDER_DATA_FILE_LIST_GTIVT)));
   end
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % next EGO file
elseif (strcmp(a_eventData.Key, 'downarrow'))
   if (length(g_GLIDER_DATA_FILE_LIST_GTIVT) > 1)
      trace_imm_vs_time( ...
         g_gliderDirNumber_GTIVT, ...
         mod(g_gliderFileNumber_GTIVT+1, length(g_GLIDER_DATA_FILE_LIST_GTIVT)));
   end
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % plot/unplot PHASE2
elseif (strcmp(a_eventData.Key, 'p'))
   if (g_plotPhase2_GTIVT == 1)
      g_plotPhase2_GTIVT = 0;
   else
      g_plotPhase2_GTIVT = 1;
   end
   trace_imm_vs_time(g_gliderDirNumber_GTIVT, g_gliderFileNumber_GTIVT);
   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
   % write help
elseif (strcmp(a_eventData.Key, 'h'))
   fprintf('\n');
   fprintf('Available commands:\n');
   fprintf('   h                : write help and current configuration\n');
   fprintf('   Left/Right arrow : previous/next directory\n');
   fprintf('   Up/Down arrow    : previous/next EGO NetCDF file\n');
   fprintf('   p                : plot/unplot PHASE2\n');
   fprintf('   Escape           : exit\n');
   fprintf('\n');
end

return

% ------------------------------------------------------------------------------
% Récupération du code couleur associé à chaque phase
%
% SYNTAX :
% [o_color] = get_color(a_phaseVal)
%
% INPUT PARAMETERS :
%   a_phaseVal : indice de la phase
%
% OUTPUT PARAMETERS :
%   o_color : couleur associé à la phase
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
% AUTHORS  : Anne Piron (Altran)(anne.piron@altran.com)
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
if (max(xTickDay) - min(xTickDay) > 2)
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
