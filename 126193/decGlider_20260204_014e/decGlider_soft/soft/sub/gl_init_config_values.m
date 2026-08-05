% ------------------------------------------------------------------------------
% Initialize configuration values.
%
% SYNTAX :
%  o_inputError = gl_init_config_values
%
% INPUT PARAMETERS :
%
% OUTPUT PARAMETERS :
%   o_inputError : input error flag
%
% EXAMPLES :
%
% SEE ALSO :
% AUTHOR : Jean-Philippe Rannou (Capgemini) (jean.philippe.rannou@partenaire-exterieur.ifremer.fr)
% ------------------------------------------------------------------------------
% RELEASES :
%   01/02/2020 - RNU - creation
% ------------------------------------------------------------------------------
function o_inputError = gl_init_config_values

% output parameters initialization
o_inputError = 0;

% global configuration values
global g_decGl_inputDataTopDir;
global g_decGl_outputLogDir;
global g_decGl_outputXmlDir;

global g_decGl_egoFormatVersion;

global g_decGl_egoFormatJsonFile;

global g_decGl_computeSlocumCurrentFlag;
global g_decGl_generateProfileFlag;

global g_decGl_generateOceanGlidersFlag;
global g_decGl_oceanGlidersFileOutputDir;

global g_decGl_applyRtqcFlag;

global g_decGl_rtqcTest2;
global g_decGl_rtqcTest3;
global g_decGl_rtqcTest4;
global g_decGl_rtqcTest6;
global g_decGl_rtqcTest7;
global g_decGl_rtqcTest9;
global g_decGl_rtqcTest11;
global g_decGl_rtqcTest15;
global g_decGl_rtqcTest19;
global g_decGl_rtqcTest20;
global g_decGl_rtqcTest25;
global g_decGl_rtqcTest57;
global g_decGl_rtqcTest59;
global g_decGl_rtqcTest63;

global g_decGl_rtqcGebcoFile;
global g_decGl_rtqcGreyList;

global g_decGl_rtqcTest8;
global g_decGl_rtqcTest12;
global g_decGl_rtqcTest13;
global g_decGl_rtqcTest14;

% configuration parameters
configVar = [];
configVar{end+1} = 'DATA_DIRECTORY';
configVar{end+1} = 'LOG_DIRECTORY';
configVar{end+1} = 'XML_DIRECTORY';

configVar{end+1} = 'EGO_FORMAT_VERSION';

configVar{end+1} = 'EGO_FORMAT_JSON_FILE';

configVar{end+1} = 'COMPUTE_SLOCUM_SUBSURFACE_CURRENT';
configVar{end+1} = 'GENERATE_PROFILE_FILES';

configVar{end+1} = 'GENERATE_OCEAN_GLIDERS_FILE';
configVar{end+1} = 'OCEAN_GLIDERS_FILE_OUTPUT_DIRECTORY';

configVar{end+1} = 'APPLY_RTQC_TESTS';

configVar{end+1} = 'TEST002_IMPOSSIBLE_DATE';
configVar{end+1} = 'TEST003_IMPOSSIBLE_LOCATION';
configVar{end+1} = 'TEST004_POSITION_ON_LAND';
configVar{end+1} = 'TEST006_GLOBAL_RANGE';
configVar{end+1} = 'TEST007_REGIONAL_RANGE';
configVar{end+1} = 'TEST009_SPIKE';
configVar{end+1} = 'TEST011_GRADIENT';
configVar{end+1} = 'TEST015_GREY_LIST';
configVar{end+1} = 'TEST019_DEEPEST_PRESSURE';
configVar{end+1} = 'TEST020_QUESTIONABLE_ARGOS_POSITION';
configVar{end+1} = 'TEST025_MEDD';
configVar{end+1} = 'TEST057_DOXY';
configVar{end+1} = 'TEST059_NITRATE';
configVar{end+1} = 'TEST063_CHLA';

configVar{end+1} = 'TEST004_GEBCO_FILE';
configVar{end+1} = 'TEST015_GREY_LIST_FILE';

configVar{end+1} = 'TEST008_PRESSURE_INCREASING';
configVar{end+1} = 'TEST012_DIGIT_ROLLOVER';
configVar{end+1} = 'TEST013_STUCK_VALUE';
configVar{end+1} = 'TEST014_DENSITY_INVERSION';

% get configuration parameters
[configVal, o_inputError] = gl_read_config_file(configVar);

if (o_inputError == 0)

   g_decGl_inputDataTopDir = configVal{1};
   g_decGl_inputDataTopDir = gl_clean_file_sep_in_path(g_decGl_inputDataTopDir, 1);
   configVal(1) = [];
   g_decGl_outputLogDir = configVal{1};
   g_decGl_outputLogDir = gl_clean_file_sep_in_path(g_decGl_outputLogDir, 1);
   configVal(1) = [];
   g_decGl_outputXmlDir = configVal{1};
   g_decGl_outputXmlDir = gl_clean_file_sep_in_path(g_decGl_outputXmlDir, 1);
   configVal(1) = [];

   g_decGl_egoFormatVersion = str2num(configVal{1});
   configVal(1) = [];

   g_decGl_egoFormatJsonFile = configVal{1};
   g_decGl_egoFormatJsonFile = gl_clean_file_sep_in_path(g_decGl_egoFormatJsonFile, 0);
   configVal(1) = [];
   
   g_decGl_computeSlocumCurrentFlag = str2num(configVal{1});
   configVal(1) = [];
   
   g_decGl_generateProfileFlag = str2num(configVal{1});
   configVal(1) = [];
   
   g_decGl_generateOceanGlidersFlag = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_oceanGlidersFileOutputDir = configVal{1};
   g_decGl_oceanGlidersFileOutputDir = gl_clean_file_sep_in_path(g_decGl_oceanGlidersFileOutputDir, 1);
   configVal(1) = [];

   g_decGl_applyRtqcFlag = str2num(configVal{1});
   configVal(1) = [];
   
   g_decGl_rtqcTest2 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest3 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest4 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest6 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest7 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest9 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest11 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest15 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest19 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest20 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest25 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest57 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest59 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest63 = str2num(configVal{1});
   configVal(1) = [];
   
   g_decGl_rtqcGebcoFile = configVal{1};
   g_decGl_rtqcGebcoFile = gl_clean_file_sep_in_path(g_decGl_rtqcGebcoFile, 0);
   configVal(1) = [];
   g_decGl_rtqcGreyList = configVal{1};
   g_decGl_rtqcGreyList = gl_clean_file_sep_in_path(g_decGl_rtqcGreyList, 0);
   configVal(1) = [];
   
   g_decGl_rtqcTest8 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest12 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest13 = str2num(configVal{1});
   configVal(1) = [];
   g_decGl_rtqcTest14 = str2num(configVal{1});
   configVal(1) = [];
   
end

return
