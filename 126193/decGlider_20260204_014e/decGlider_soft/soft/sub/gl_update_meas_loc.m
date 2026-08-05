% ------------------------------------------------------------------------------
% Interpolate the (not already located) locations of the timeseries using GPS
% and glider locations.
%
% SYNTAX :
%  gl_update_meas_loc(a_ncFileName, a_applyRtqc)
%
% INPUT PARAMETERS :
%   a_ncFileName : EGO netCDF file path name
%   a_applyRtqc  : RTQC tests have been applied on input EGO file data
%
% OUTPUT PARAMETERS :
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   04/12/2016 - RNU - creation
% ------------------------------------------------------------------------------
function gl_update_meas_loc(a_ncFileName, a_applyRtqc)

% QC flag values
global g_decGl_qcGood;
global g_decGl_qcInterpolated;


% check if the file exists
if (~exist(a_ncFileName, 'file'))
   fprintf('ERROR: File not found : %s\n', a_ncFileName);
   return
end

% open NetCDF file
fCdf = netcdf.open(a_ncFileName, 'NC_WRITE');
if (isempty(fCdf))
   fprintf('ERROR: Unable to open NetCDF input file: %s\n', a_ncFileName);
   return
end

if (gl_var_is_present(fCdf, 'TIME') && ...
      gl_var_is_present(fCdf, 'LATITUDE') && ...
      gl_var_is_present(fCdf, 'LONGITUDE'))

   % retrieve location data
   time = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'TIME'));
   timeQc = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'TIME_QC'));
   longitude = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'LONGITUDE'));
   latitude = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'LATITUDE'));
   positionQc = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'POSITION_QC'));

   % retrieve fill values
   timeFillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, 'TIME'), '_FillValue');
   lonFillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, 'LONGITUDE'), '_FillValue');
   latFillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, 'LATITUDE'), '_FillValue');
   posMethodFillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, 'POSITIONING_METHOD'), '_FillValue');

   % interpolate the GPS fixes (and, for slocum, the glider fixes, if any) along the TIME dimension

   % retrieve GPS reference location data
   timeRef = [];
   longitudeRef = [];
   latitudeRef = [];
   if (gl_var_is_present(fCdf, 'TIME_GPS'))
      timeRef = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'TIME_GPS'));
      timeRefQc = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'TIME_GPS_QC'));
      longitudeRef = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'LONGITUDE_GPS'));
      latitudeRef = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'LATITUDE_GPS'));
      positionRefQc = netcdf.getVar(fCdf, netcdf.inqVarID(fCdf, 'POSITION_GPS_QC'));

      % retrieve associated fill values
      timeRefFillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, 'TIME_GPS'), '_FillValue');
      lonRefFillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, 'LONGITUDE_GPS'), '_FillValue');
      latRefFillVal = netcdf.getAtt(fCdf, netcdf.inqVarID(fCdf, 'LATITUDE_GPS'), '_FillValue');

      if (a_applyRtqc == 1)
         idOk = find((timeRef ~= timeRefFillVal) & (longitudeRef ~= lonRefFillVal) & (latitudeRef ~= latRefFillVal) & ...
            (timeRefQc == g_decGl_qcGood) & (positionRefQc == g_decGl_qcGood));
      else
         idOk = find((timeRef ~= timeRefFillVal) & (longitudeRef ~= lonRefFillVal) & (latitudeRef ~= latRefFillVal));
      end

      timeRef = timeRef(idOk);
      longitudeRef = longitudeRef(idOk);
      latitudeRef = latitudeRef(idOk);
   end

   % add glider reference location data
   if (a_applyRtqc == 1)
      idOk = find((time ~= timeFillVal) & (longitude ~= lonFillVal) & (latitude ~= latFillVal) & ...
         (timeQc == g_decGl_qcGood) & (positionQc == g_decGl_qcGood));
   else
      idOk = find((time ~= timeFillVal) & (longitude ~= lonFillVal) & (latitude ~= latFillVal));
   end
   timeRef = [timeRef; time(idOk)];
   longitudeRef = [longitudeRef; longitude(idOk)];
   latitudeRef = [latitudeRef; latitude(idOk)];

   % set POSIIONING_METHOD
   positioningMethod = int8(ones(size(time)))*posMethodFillVal;
   idGliderPos = find((longitude ~= lonFillVal) & (latitude ~= latFillVal));
   positioningMethod(idGliderPos) = 3;

   % interpolate measurement locations
   if (length(longitudeRef) > 1)

      [timeRef, idSort] = sort(timeRef);
      longitudeRef = longitudeRef(idSort);
      latitudeRef = latitudeRef(idSort);

      if (a_applyRtqc == 1)
         idOk = find((time ~= timeFillVal) & (timeQc == g_decGl_qcGood) & ...
            (longitude == lonFillVal) & (latitude == latFillVal));
      else
         idOk = find((time ~= timeFillVal) & ...
            (longitude == lonFillVal) & (latitude == latFillVal));
      end

      longitude(idOk) = interp1q(timeRef, longitudeRef, time(idOk));
      latitude(idOk) = interp1q(timeRef, latitudeRef, time(idOk));

      idInter = setdiff(idOk, idOk(isnan(longitude(idOk))));

      longitude(isnan(longitude)) = lonFillVal;
      latitude(isnan(latitude)) = latFillVal;

      positioningMethod(idInter) = 2;
      positionQc(idInter) = g_decGl_qcInterpolated;
   end

   % there is no need to apply RTQC tests #4 (position on land) and #20
   % (questionable Argos position) once again because base position used for
   % interpolation (GPS ones and glider ones if they have been imported from input
   % data) have already succeeded test #4 and #20

   % update the EGO file data
   netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'LATITUDE'), latitude);
   netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'LONGITUDE'), longitude);
   netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'POSITION_QC'), positionQc);
   netcdf.putVar(fCdf, netcdf.inqVarID(fCdf, 'POSITIONING_METHOD'), positioningMethod);

end

netcdf.close(fCdf);

return
