% ------------------------------------------------------------------------------
% Compute and add PHASE and PHASE_NUMBER parameter in an EGO netCDF file.
%
% SYNTAX :
%  gl_set_phase(a_ncFileName)
%
% INPUT PARAMETERS :
%   a_ncFileName : EGO netCDF file path name
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   06/07/2013 - RNU - creation
%   14/04/2014 - TCA - NB bin for profiles set to 10 instead of 1
% ------------------------------------------------------------------------------
function gl_set_phase(a_ncFileName)

% PHASE codes
global g_decGl_phaseSurfDrift;
global g_decGl_phaseDescent;
global g_decGl_phaseSubSurfDrift;
global g_decGl_phaseInflexion;
global g_decGl_phaseAscent;
global g_decGl_phaseGrounded;
global g_decGl_phaseInconsistant;
global g_decGl_phaseDefault;

% flag for HR data
global g_decGl_hrDataFlag;

% type of the glider to process
global g_decGl_gliderType;

% add PHASE2 computed from technical data
global g_decGl_addPhase2;


% verbose mode flag
VERBOSE_MODE = 0;

% main parameters of the algorithm

% maximal pressure for the measurements (in dbar)
MAX_PRESSURE = 2500;

% maximal vertical velocity between 2 measurements (in cm/s)
MAX_VERTICAL_VELOCITY = 100;

% sampling period used to comppute vertical speed threshold
MIN_SAMPLING_PERIOD_FOR_VERTICAL_SPEED_SECOND = 30;
MAX_SAMPLING_PERIOD_FOR_VERTICAL_SPEED_SECOND = 10*MIN_SAMPLING_PERIOD_FOR_VERTICAL_SPEED_SECOND;

% part of the data set needed to define the list of main modes 
PART_OF_POINTS_FOR_MODE_SELECTION_PERCENT = 80;

% part of the minimum main mode used to define the threshold for ascent/descent
% measurements
PART_OF_MIN_MODE_FOR_THRESHOLD = 1/4;

% minimum duration of a profile
NB_BIN_MIN_FOR_PROFILE = 10;
MIN_DURATION_FOR_PROFILE_SECOND = MIN_SAMPLING_PERIOD_FOR_VERTICAL_SPEED_SECOND*NB_BIN_MIN_FOR_PROFILE;

% part of the measurements used to detect that the glider profiles in only one
% direction
MONO_DIRECTION_PROFILE_THRESHOLD = 70/100;

% maximum immersion for a glider at the surface
THRESHOLD_PRES_FOR_SURF = 2;

% maximal duration (in minutes) of an inflexion
MAX_DURATION_OF_INFLEXION = 10;


% check if the file exists
if (~exist(a_ncFileName, 'file'))
   fprintf('ERROR: File not found : %s\n', a_ncFileName);
   return
end

% fprintf('INFO: Processing file : %s\n', a_ncFileName);

% open NetCDF file
fCdf = netcdf.open(a_ncFileName, 'NC_WRITE');
if (isempty(fCdf))
   fprintf('ERROR: Unable to open NetCDF input file: %s\n', a_ncFileName);
   return
end

% retrieve immersion data
immVarId = [];
presFillValId = [];
if (gl_var_is_present(fCdf, 'PRES'))
   presDataOri = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'PRES'));
   presFillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, 'PRES'), '_FillValue');
   presFillValId = find(presDataOri == presFillVal);
   immVarId = netcdf.inqVarID(fCdf, 'PRES');
elseif (gl_var_is_present(fCdf, 'DEPTH'))
   presDataOri = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'DEPTH'));
   presFillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, 'DEPTH'), '_FillValue');
   presFillValId = find(presDataOri == presFillVal);
   immVarId = netcdf.inqVarID(fCdf, 'DEPTH');
else
   fprintf('ERROR: Variable %s (nor %s) not present in file : %s\n', ...
      'PRES', 'DEPTH', a_ncFileName);
   netcdf.close(fCdf);
   return
end

% retrieve time data
[varname, xtype, immDimId, natts] = netcdf.inqVar(fCdf, immVarId);
if (size(immDimId, 2) ~= 1)
   fprintf('ERROR: Inconcistent dimension for immersion variable in file : %s\n', ...
      a_ncFileName);
   netcdf.close(fCdf);
   return
end
[timeVar, dimlen] = netcdf.inqDim(fCdf, immDimId);
if (gl_var_is_present(fCdf, timeVar))
   timeDataOri = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, timeVar));
else
   fprintf('ERROR: Variable %s not present in file : %s\n', ...
      timeVar, a_ncFileName);
   netcdf.close(fCdf);
   return
end

% check data size
if (length(timeDataOri) ~= length(presDataOri))
   fprintf('ERROR: Time and immersion data must have the same size\n');
   netcdf.close(fCdf);
   return
end

% check for PHASE and PHASE_NUMBER variables
if (~gl_var_is_present(fCdf, 'PHASE'))
   fprintf('ERROR: Variable %s not present in file : %s\n', ...
      'PHASE', a_ncFileName);
   netcdf.close(fCdf);
   return
end
if (~gl_var_is_present(fCdf, 'PHASE_NUMBER'))
   fprintf('ERROR: Variable %s not present in file : %s\n', ...
      'PHASE_NUMBER', a_ncFileName);
   netcdf.close(fCdf);
   return
end

% check PHASE and PHASE_NUMBER variable dimensions
if (length(netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'PHASE'))) ~= ...
      length(netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'PHASE_NUMBER'))))
   fprintf('ERROR: PHASE and PHASE_NUMBER variables must have the same dimension\n');
   netcdf.close(fCdf);
   return
end
if (length(netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'PHASE'))) ~= ...
      length(presDataOri))
   fprintf('ERROR: Time, immersion, PHASE and PHASE_NUMBER variables must have the same dimension\n');
   netcdf.close(fCdf);
   return
end

% compute PHASE and PHASE_NUMBER parameters
phaseDataFinalMin = int8(ones(length(timeDataOri)-length(presFillValId), 1))*g_decGl_phaseDefault;
phaseNumberDataFinalMin = ones(length(timeDataOri)-length(presFillValId), 1)*99999;
phaseDataFinalTotal = int8(ones(length(timeDataOri), 1))*g_decGl_phaseDefault;
phaseNumberDataFinalTotal = ones(length(timeDataOri), 1)*99999;

% do not consider measurements timely too close (they induce huge vertical
% speeds and possibly memory problems when computing the modes)
idDelInOri = [];
if (~isempty(timeDataOri) && ~isempty(presDataOri))
   
   timeData = timeDataOri;
   presData = presDataOri;
   timeData(presFillValId) = [];
   presData(presFillValId) = [];
   if (length(timeData) > 1)
      
      idDataOri = 1:length(timeData);
      idData = idDataOri;
      idDel = find(abs(presData) > MAX_PRESSURE);
      timeData(idDel) = [];
      presData(idDel) = [];
      idData(idDel) = [];
      
      if (length(timeData) > 1)
         % vertical velocities in cm/s
         vertVel = diff(presData)*100./diff(timeData);
         
         idDel = find((abs(vertVel) > MAX_VERTICAL_VELOCITY) | (vertVel == 0));
         timeData(idDel) = [];
         presData(idDel) = [];
         idData(idDel) = [];
      end
      
      idDelInOri = setdiff(idDataOri, idData);
   end

   if (~isempty(timeData) && ~isempty(presData))

      phaseData = int8(ones(length(timeData), 1))*g_decGl_phaseDefault;
      phaseNumberData = zeros(length(timeData), 1);
      
      if (length(timeData) > 2)
         
         if (VERBOSE_MODE == 1)
            fprintf('Sampling period (sec): mean %g stdev %g min %g max %g\n', ...
               mean(diff(timeData)), std(diff(timeData)), ...
               min(diff(timeData)), max(diff(timeData)));
         end
         
         % compute PHASE parameter
         
         if (median(diff(timeData)) ~= 0)
            samplingPeriodMed = median(diff(timeData));
         else
            timeDiff = diff(timeData);
            timeDiff(timeDiff == 0) = [];
            samplingPeriodMed = median(timeDiff);
         end

         % vertical velocities in cm/s
         if (~g_decGl_hrDataFlag)
            vertVel = diff(presData)*100./diff(timeData);
         else
            idStart = 1;
            idStop = idStart + 1;
            stop = 0;
            vertVel = nan(length(timeData)-1, 1);
            while (~stop)
               while ((idStop <= length(timeData)) && ((timeData(idStop)-timeData(idStart)) < MIN_SAMPLING_PERIOD_FOR_VERTICAL_SPEED_SECOND))
                  idStop = idStop + 1;
               end
               if (idStop > length(timeData))
                  idStop = idStop - 1;
               end
               if ((timeData(idStop)-timeData(idStart)) > MAX_SAMPLING_PERIOD_FOR_VERTICAL_SPEED_SECOND)
                  if (idStop-idStart > 1)
                     idStop = idStop - 1;
                  end
               end
               %             gl_julian_2_gregorian(gl_epoch_2_julian((timeData(idStart:idStop))))
               vertVel(idStart:idStop-1) = (presData(idStop)-presData(idStart))*100./(timeData(idStop)-timeData(idStart));
               %             timeData(idStop)-timeData(idStart)
               idStart = idStop;
               idStop = idStart + 1;
               if (idStop > length(timeData))
                  stop = 1;
               end
            end
         end

         % find and sort the modes of the velocity dataset
         [modeNb, modeVal] = hist(vertVel, floor(min(vertVel)):0.5:ceil(max(vertVel)));
         [modeNb, idSort] = sort(modeNb, 'descend');
         modeVal = modeVal(idSort);
         modeNb = modeNb*100/length(vertVel);
         
         % delete the mode 0, i.e. in the [-0.5; +0.5] bin
         idDel = find(modeVal == 0);
         nbForMode0 = sum(modeNb(idDel));
         modeNb(idDel) =[];
         modeVal(idDel) =[];
         
         % compute the vertical threshold used to identify ascent and descent data
         if (~isempty(modeVal))
            % find the main modes that gathered more than
            % PART_OF_POINTS_FOR_MODE_SELECTION_PERCENT % of the data set (taking
            % into account the data of mode 0)
            idM = 1;
            while (sum(modeNb(1:idM)) < PART_OF_POINTS_FOR_MODE_SELECTION_PERCENT-nbForMode0)
               idM = idM + 1;
            end
            
            if (VERBOSE_MODE == 1)
               %                fprintf('Modes:\n');
               %                for id = 1:idM
               %                   fprintf('-> %2d : %.1f %5.1f\n', ...
               %                      id, modeVal(id),modeNb(id));
               %                end
               %                for id = idM+1:min(length(modeVal), idM+3)
               %                   fprintf('   %2d : %.1f %5.1f\n', ...
               %                      id, modeVal(id),modeNb(id));
               %                end
            end

            % the vertical threshold is PART_OF_MIN_MODE_FOR_THRESHOLD of the
            % minimum of the main modes
            vertVelThreshold = min(abs(modeVal(1:idM)))*PART_OF_MIN_MODE_FOR_THRESHOLD;

            % use the threshold to identify ascent and descent data
            idModePos = find(vertVel > vertVelThreshold);
            idModeNeg = find(vertVel < -vertVelThreshold);
            phaseData(idModePos+1) = g_decGl_phaseDescent;
            phaseData(idModeNeg+1) = g_decGl_phaseAscent;
            if (VERBOSE_MODE == 1)
               fprintf('Threshold: %.1f (cm/s)\n', vertVelThreshold);
            end
            
            % try to set the phase of the first point of the time series
            if (phaseData(2) == g_decGl_phaseDescent) && (presData(1) < presData(2))
               phaseData(1) = g_decGl_phaseDescent;
            end
            if (phaseData(2) == g_decGl_phaseAscent) && (presData(1) > presData(2))
               phaseData(1) = g_decGl_phaseAscent;
            end
         end
         
         % set to g_decGl_phaseDefault the points of too short profiles
         % (less than MIN_DURATION_FOR_PROFILE_SECOND seconds)
         if (~g_decGl_hrDataFlag)
            nbLevelMinForProfile = NB_BIN_MIN_FOR_PROFILE;
         else
            nbLevelMinForProfile = MIN_DURATION_FOR_PROFILE_SECOND/samplingPeriodMed;
         end
         [tabStart, tabStop] = gl_get_intervals(find(phaseData == g_decGl_phaseDescent));
         for id = 1:length(tabStart)
            idStart = tabStart(id);
            idStop = tabStop(id);
            if (idStop-idStart+1 < nbLevelMinForProfile)
               phaseData(idStart:idStop) = g_decGl_phaseDefault;
            end
         end
         [tabStart, tabStop] = gl_get_intervals(find(phaseData == g_decGl_phaseAscent));
         for id = 1:length(tabStart)
            idStart = tabStart(id);
            idStop = tabStop(id);
            if (idStop-idStart+1 < nbLevelMinForProfile)
               phaseData(idStart:idStop) = g_decGl_phaseDefault;
            end
         end
         
         % for gliders which profile in only one direction: split the data
         % according to a threshold based on the descent/ascent min duration
         
         minDur = 365*86400;
         idDescent = find(phaseData == g_decGl_phaseDescent);
         nbDescent = length(idDescent);
         idAscent = find(phaseData == g_decGl_phaseAscent);
         nbAscent = length(idAscent);
         profDir = 0;
         % the glider profile in only one direction if
         % MONO_DIRECTION_PROFILE_THRESHOLD of its data are in descent or ascent
         if (((nbDescent/length(phaseData)) > MONO_DIRECTION_PROFILE_THRESHOLD) || ...
               ((nbAscent/length(phaseData)) > MONO_DIRECTION_PROFILE_THRESHOLD))
            % one direction profiling glider
            
            % compute the min duration of the ascent/descent profile
            if (nbDescent > nbAscent)
               profDir = -1;
               trans = find(diff(presData(idDescent)) < 0);
               idStart = idDescent(1);
               for id = 1:length(trans)+1
                  if (id <= length(trans))
                     idStop = idDescent(trans(id));
                  else
                     idStop = idDescent(end);
                  end
                  
                  minDur = min(minDur, timeData(idStop)-timeData(idStart));
                  
                  if (id <= length(trans))
                     idStart = idDescent(trans(id)+1);
                  end
               end
            else
               profDir = 1;
               trans = find(diff(presData(idAscent)) > 0);
               idStart = idAscent(1);
               for id = 1:length(trans)+1
                  if (id <= length(trans))
                     idStop = idAscent(trans(id));
                  else
                     idStop = idAscent(end);
                  end
                  
                  minDur = min(minDur, timeData(idStop)-timeData(idStart));
                  
                  if (id <= length(trans))
                     idStart = idAscent(trans(id)+1);
                  end
               end
            end
         end
         
         % split the data with a minDur/2 threshold
         tabStart = [];
         tabStop = [];
         trans = find(diff(timeData) > minDur/2);
         idStart = 1;
         for id = 1:length(trans)+1
            if (id <= length(trans))
               idStop = trans(id);
            else
               idStop = length(timeData);
            end
            
            tabStart = [tabStart; idStart];
            tabStop = [tabStop; idStop];
            
            if (id <= length(trans))
               idStart = trans(id)+1;
            end
         end
         
         % process the splitted data set and find the PHASE of the remaining (PHASE
         % == g_decGl_phaseDefault) measurements
         for idPart = 1:length(tabStart)
            idPartStart = tabStart(idPart);
            idPartStop = tabStop(idPart);
            phasePart = phaseData(idPartStart:idPartStop);
            pressPart = presData(idPartStart:idPartStop);
            timePart = timeData(idPartStart:idPartStop);
            
            % process only slices of measurements with the same PHASE (==
            % g_decGl_phaseDefault)
            trans = find(diff(phasePart) ~= 0);
            idStart = 1;
            for id = 1:length(trans)+1
               if (id <= length(trans))
                  idStop = trans(id);
               else
                  idStop = length(phasePart);
               end
               idList = idStart:idStop;
               
               if (phasePart(idStart) == g_decGl_phaseDefault)
                  
                  if ((idPart == 1) && (id == 1))
                     % slice which begin the time series
                     
                     % surface drift if immersion is less than
                     % THRESHOLD_PRES_FOR_SURF dbars
                     idSurf = find(abs(pressPart(idList)) < THRESHOLD_PRES_FOR_SURF);
                     if (~isempty(idSurf))
                        if (isempty(find(diff(idSurf) ~= 1, 1)) && (idList(idSurf(end)) == idList(end)))
                           phasePart(idList(idSurf)) = g_decGl_phaseSurfDrift;
                        end
                     end
                     % otherwise: inconsistant measurements if descent profile or
                     % inflexion measurement if ascent profile
                     idNoSurf = find(abs(pressPart(idList)) >= THRESHOLD_PRES_FOR_SURF);
                     if (~isempty(idNoSurf))
                        if (isempty(find(diff(idNoSurf) ~= 1, 1)) && (idList(idNoSurf(1)) == idList(1)))
                           if (profDir <= 0)
                              phasePart(idList(idNoSurf)) = g_decGl_phaseInconsistant;
                           else
                              phasePart(idList(idNoSurf)) = g_decGl_phaseInflexion;
                           end
                        end
                     end
                     
                  else
                     
                     surfDrift = 0;
                     if ((idPart == length(tabStart)) && (id == length(trans)+1))
                        % surface drift at the end of the time series
                        idSurf = find(abs(pressPart(idList)) < THRESHOLD_PRES_FOR_SURF);
                        if (~isempty(idSurf))
                           if (isempty(find(diff(idSurf) ~= 1, 1)) && (idList(idSurf(1)) == idList(1)))
                              phasePart(idList(idSurf)) = g_decGl_phaseSurfDrift;
                              surfDrift = 1;
                           end
                        end
                     end
                     
                     if (surfDrift == 0)
                        % between beginning and end slices of the time series we
                        % can have:
                        % - inflexion measurements if the duration of the slice is
                        % less than MAX_DURATION_OF_INFLEXION
                        % - surface or subsurface drift depending of the immersion
                        % criteria (THRESHOLD_PRES_FOR_SURF threshold
                        phaseDuration = (timePart(idStop)-timePart(idStart))/60;
                        if (phaseDuration <= MAX_DURATION_OF_INFLEXION)
                           phasePart(idList) = g_decGl_phaseInflexion;
                        else
                           if (isempty(find(abs(pressPart(idList)) >= THRESHOLD_PRES_FOR_SURF, 1)))
                              phasePart(idList) = g_decGl_phaseSurfDrift;
                           else
                              phasePart(idList) = g_decGl_phaseSubSurfDrift;
                           end
                        end
                     end
                     
                  end
               end
               
               if (id <= length(trans))
                  idStart = trans(id)+1;
               end
            end
            
            phaseData(idPartStart:idPartStop) = phasePart;
         end
         
         % compute PHASE_NUMBER parameter
         numPhase = 0;
         for idPart = 1:length(tabStart)
            idPartStart = tabStart(idPart);
            idPartStop = tabStop(idPart);
            phasePart = phaseData(idPartStart:idPartStop);
            pressPart = presData(idPartStart:idPartStop);
            timePart = timeData(idPartStart:idPartStop);
            phaseNumberPart = phaseNumberData(idPartStart:idPartStop);
            
            trans = find(diff(phasePart) ~= 0);
            idStart = 1;
            for id = 1:length(trans)+1
               if (id <= length(trans))
                  idStop = trans(id);
               else
                  idStop = length(phasePart);
               end
               
               if (VERBOSE_MODE == 1)
                  fprintf('Phase #%04d (%s):   %5d pts   %7.1f sec   %s   minP %7.1f dbar   maxP %7.1f dbar\n', ...
                     numPhase, gl_get_phase_name(phasePart(idStart)), ...
                     idStop-idStart+1, ...
                     timePart(idStop)-timePart(idStart), ...
                     gl_format_time2((timePart(idStop)-timePart(idStart))/3600), ...
                     min(pressPart(idStart:idStop)), max(pressPart(idStart:idStop)));
               end
               
               phaseNumberPart(idStart:idStop) = numPhase;
               numPhase = numPhase + 1;
               
               if (id <= length(trans))
                  idStart = trans(id)+1;
               end
            end
            
            phaseNumberData(idPartStart:idPartStop) = phaseNumberPart;
         end
      end

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % remove litle inflexions in ascent/descent phases

      % phase codes
      CODE_DESCENT = 1;
      CODE_ASCENT = 4;

      phaseInfo = [];
      descPhaseNum = unique(phaseNumberData(phaseData == int8(CODE_DESCENT)));
      for num = descPhaseNum'
         idStart = find(phaseNumberData == num, 1, 'first');
         idStop = find(phaseNumberData == num, 1, 'last');
         phaseInfo = [phaseInfo; [CODE_DESCENT num idStart idStop]];
      end
      ascPhaseNum = unique(phaseNumberData(phaseData == int8(CODE_ASCENT)));
      for num = ascPhaseNum'
         idStart = find(phaseNumberData == num, 1, 'first');
         idStop = find(phaseNumberData == num, 1, 'last');
         phaseInfo = [phaseInfo; [CODE_ASCENT num idStart idStop]];
      end

      if (~isempty(phaseInfo))

         DELTA_PRES = 10;

         [~, idSort] = sort(phaseInfo(:, 2));
         phaseInfo = phaseInfo(idSort, :);

         stop = 0;
         curId = 2;
         cor = 0;
         while (~stop && curId <= size(phaseInfo, 1))
            if (phaseInfo(curId, 1) == phaseInfo(curId-1, 1))
               if (phaseInfo(curId, 1) == CODE_DESCENT)
                  if (presData(phaseInfo(curId-1, 4)) <= presData(phaseInfo(curId, 3)) + DELTA_PRES)
                     phaseInfo(curId-1, 4) = phaseInfo(curId, 4);
                     phaseInfo(curId, :) = [];
                     cor = 1;
                  else
                  curId = curId + 1;
                  end
               else
                  if (presData(phaseInfo(curId-1, 4)) >= presData(phaseInfo(curId, 3)) - DELTA_PRES)
                     phaseInfo(curId-1, 4) = phaseInfo(curId, 4);
                     phaseInfo(curId, :) = [];
                     cor = 1;
                  else
                  curId = curId + 1;
                  end
               end
            else
               curId = curId + 1;
            end
         end

         if (cor)
            for idL = 1:size(phaseInfo, 1)
               phaseData(phaseInfo(idL, 3):phaseInfo(idL, 4)) = int8(phaseInfo(idL, 1));
               phaseNumberData(phaseInfo(idL, 3):phaseInfo(idL, 4)) = phaseInfo(idL, 2);
            end
         end
      end
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

      % complete the final PHASE and PHASE NUMBER data
      if (~isempty(idDelInOri))
         idNotDelInOri = setdiff(1:length(phaseDataFinalMin), idDelInOri);
         phaseDataFinalMin(idNotDelInOri) = phaseData;
         phaseNumberDataFinalMin(idNotDelInOri) = phaseNumberData;

         id = length(phaseDataFinalMin)-1;
         while (id > 0)
            if (phaseDataFinalMin(id) == g_decGl_phaseDefault)
               phaseDataFinalMin(id) = phaseDataFinalMin(id+1);
               phaseNumberDataFinalMin(id) = phaseNumberDataFinalMin(id+1);
            end
            id = id - 1;
         end
      else
         phaseDataFinalMin = phaseData;
         phaseNumberDataFinalMin = phaseNumberData;
      end
   end
   
   phaseDataFinalTotal(setdiff(1:length(timeDataOri), presFillValId)) = phaseDataFinalMin;
   phaseNumberDataFinalTotal(setdiff(1:length(timeDataOri), presFillValId)) = phaseNumberDataFinalMin;
   
   % store PHASE and PHASE_NUMBER data in the netCDF file
   netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'PHASE'), phaseDataFinalTotal);
   netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'PHASE_NUMBER'), phaseNumberDataFinalTotal);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% compute PHASE2 and PHASE_NUMBER2 parameters

if (g_decGl_addPhase2 == 1)

   % for slocum
   if (strcmp(g_decGl_gliderType, 'slocum'))
      buoyDataOri = [];
      if (gl_var_is_present(fCdf, 'TECH_ballast_pumped'))
         inputData = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'TECH_ballast_pumped'));
         fillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, 'TECH_ballast_pumped'), '_FillValue');
         if (any(inputData ~= fillVal))
            if (any(inputData(inputData ~= fillVal) ~= 0))
               buoyDataOri = inputData;
               buoyDataFillValue = fillVal;
            end
         end
      end
      if (~isempty(buoyDataOri))

         phaseDataFinalTotal2 = int8(ones(length(timeDataOri), 1))*g_decGl_phaseDefault;
         phaseNumberDataFinalTotal2 = ones(length(timeDataOri), 1)*99999;

         if (any(buoyDataOri == buoyDataFillValue))

            idNoDef = find(buoyDataOri ~= buoyDataFillValue);
            if (length(idNoDef) > 1)
               idDef = find(buoyDataOri == buoyDataFillValue);
               buoyDataOri(idDef) = interp1q(timeDataOri(idNoDef), buoyDataOri(idNoDef), timeDataOri(idDef));
               buoyDataOri(isnan(buoyDataOri)) = buoyDataFillValue;
            end
         end

         idNoDef = find(buoyDataOri ~= buoyDataFillValue);

         inputData = buoyDataOri(idNoDef);
         phaseDataFinal2 = phaseDataFinalTotal2(idNoDef);
         phaseNumberDataFinal2 = phaseNumberDataFinalTotal2(idNoDef);

         phaseDataFinal2(inputData > 0) = int8(g_decGl_phaseAscent);
         phaseDataFinal2(inputData < 0) = int8(g_decGl_phaseDescent);

         idSet = find(diff(phaseDataFinal2) ~= 0);
         phaseNum = 1;
         for idS = 1:length(idSet)
            if (idS == 1)
               phaseNumberDataFinal2(1:idSet(idS)) = phaseNum;
            elseif (idS == length(idSet))
               phaseNumberDataFinal2(idSet(idS-1)+1:idSet(idS)) = phaseNum;
               phaseNum = phaseNum + 1;
               phaseNumberDataFinal2(idSet(idS)+1:end) = phaseNum;
            else
               phaseNumberDataFinal2(idSet(idS-1)+1:idSet(idS)) = phaseNum;
            end
            phaseNum = phaseNum + 1;
         end

         phaseDataFinalTotal2(idNoDef) = phaseDataFinal2;
         phaseNumberDataFinalTotal2(idNoDef) = phaseNumberDataFinal2;

         % store PHASE2 and PHASE_NUMBER2 data in the netCDF file
         netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'PHASE2'), phaseDataFinalTotal2);
         netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'PHASE_NUMBER2'), phaseNumberDataFinalTotal2);
      end
   end

   % for seaexplorer
   if (strcmp(g_decGl_gliderType, 'seaexplorer'))
      ballastVar = 'TECH_ballast_pumped';
      if (gl_var_is_present(fCdf, ballastVar))

         phaseDataFinalTotal2 = int8(ones(length(timeDataOri), 1))*g_decGl_phaseDefault;
         phaseNumberDataFinalTotal2 = ones(length(timeDataOri), 1)*99999;

         ballastDataOri = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, ballastVar));
         ballastPosFillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, ballastVar), '_FillValue');
         if (any(ballastDataOri == ballastPosFillVal))

            idNoDef = find(ballastDataOri ~= ballastPosFillVal);
            if (length(idNoDef) > 1)
               idDef = find(ballastDataOri == ballastPosFillVal);
               ballastDataOri(idDef) = interp1q(timeDataOri(idNoDef), ballastDataOri(idNoDef), timeDataOri(idDef));
               ballastDataOri(isnan(ballastDataOri)) = ballastPosFillVal;
            end
         end

         idNoDef = find(ballastDataOri ~= ballastPosFillVal);

         ballastData = ballastDataOri(idNoDef);
         phaseDataFinal2 = phaseDataFinalTotal2(idNoDef);
         phaseNumberDataFinal2 = phaseNumberDataFinalTotal2(idNoDef);

         phaseDataFinal2(ballastData >= 0) = int8(g_decGl_phaseAscent);
         phaseDataFinal2(ballastData < 0) = int8(g_decGl_phaseDescent);

         idSet = find(diff(phaseDataFinal2) ~= 0);
         phaseNum = 1;
         for idS = 1:length(idSet)
            if (idS == 1)
               phaseNumberDataFinal2(1:idSet(idS)) = phaseNum;
            elseif (idS == length(idSet))
               phaseNumberDataFinal2(idSet(idS-1)+1:idSet(idS)) = phaseNum;
               phaseNum = phaseNum + 1;
               phaseNumberDataFinal2(idSet(idS)+1:end) = phaseNum;
            else
               phaseNumberDataFinal2(idSet(idS-1)+1:idSet(idS)) = phaseNum;
            end
            phaseNum = phaseNum + 1;
         end

         phaseDataFinalTotal2(idNoDef) = phaseDataFinal2;
         phaseNumberDataFinalTotal2(idNoDef) = phaseNumberDataFinal2;

         % store PHASE2 and PHASE_NUMBER2 data in the netCDF file
         netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'PHASE2'), phaseDataFinalTotal2);
         netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'PHASE_NUMBER2'), phaseNumberDataFinalTotal2);
      end
   end
end

netcdf.close(fCdf);

return

% ------------------------------------------------------------------------------
% Retrieve the start and stop indices of the measurements of a given phase.
%
% SYNTAX :
%  [o_tabStart o_tabStop] = gl_get_intervals(a_indices)
%
% INPUT PARAMETERS :
%   a_indices : indices of the measurements of a given phase
%
% OUTPUT PARAMETERS :
%   o_tabStart : start indices
%   o_tabStop  : stop indices
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   06/07/2013 - RNU - creation
% ------------------------------------------------------------------------------
function [o_tabStart, o_tabStop] = gl_get_intervals(a_indices)

o_tabStart = [];
o_tabStop = [];

if (~isempty(a_indices))
   o_tabStart = [];
   o_tabStop = [];

   idStart = a_indices(1);
   trans = find(diff(a_indices) ~= 1);
   for id = 1:length(trans)+1
      if (id <= length(trans))
         idStop = a_indices(trans(id));
      else
         idStop = a_indices(end);
      end
      %          fprintf('idStart %d idStop %d\n', idStart, idStop);
      o_tabStart = [o_tabStart; idStart];
      o_tabStop = [o_tabStop; idStop];
      if (id <= length(trans))
         idStart = a_indices(trans(id)+1);
      end
   end
end

return

% ------------------------------------------------------------------------------
% Retrieve the phase name for a given phase code.
%
% SYNTAX :
%  [o_phaseName] = gl_get_phase_name(a_phaseVal)
%
% INPUT PARAMETERS :
%   a_phaseVal : phase code
%
% OUTPUT PARAMETERS :
%   o_phaseName : phase name
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   06/07/2013 - RNU - creation
% ------------------------------------------------------------------------------
function [o_phaseName] = gl_get_phase_name(a_phaseVal)

global g_decGl_phaseSurfDrift;
global g_decGl_phaseDescent;
global g_decGl_phaseSubSurfDrift;
global g_decGl_phaseInflexion;
global g_decGl_phaseAscent;
global g_decGl_phaseInconsistant;
global g_decGl_phaseDefault;

o_phaseName = [];

phaseVal = unique(a_phaseVal);
if (length(phaseVal) ~= 1)
   fprintf('ERROR: many phase values!\n');
   return
end

switch phaseVal
   case g_decGl_phaseSurfDrift
      o_phaseName = 'surface drift   ';
   case g_decGl_phaseDescent
      o_phaseName = 'descent         ';
   case g_decGl_phaseSubSurfDrift
      o_phaseName = 'subsurface drift';
   case g_decGl_phaseInflexion
      o_phaseName = 'inflexion       ';
   case g_decGl_phaseAscent
      o_phaseName = 'ascent          ';
   case g_decGl_phaseInconsistant
      o_phaseName = 'inconsistant    ';
   case g_decGl_phaseDefault
      o_phaseName = 'default value   ';
   otherwise
      fprintf('Undefined name for this phase value!\n');
end

return
