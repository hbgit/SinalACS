import { Config } from '@remotion/cli/config';

Config.setVideoImageFormat('jpeg');
Config.setOverwriteOutput(true);

// A camada de legendas precisa de alfa; os alvos com alfa são sobrescritos na
// linha de comando (ver os scripts render:subtitles no package.json).
Config.setPixelFormat('yuv420p');
Config.setCodec('h264');
Config.setCrf(18);
