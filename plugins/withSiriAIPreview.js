const { withXcodeProject } = require('expo/config-plugins');

const FLAG = 'SIRI_AI_PREVIEW';

/** Turns on the Siri AI code in app-intents/ when prebuilding with SIRI_AI_PREVIEW=1. */
module.exports = (config) =>
  withXcodeProject(config, (next) => {
    if (process.env[FLAG] !== '1') return next;
    const configurations = next.modResults.pbxXCBuildConfigurationSection();
    for (const entry of Object.values(configurations)) {
      if (entry?.buildSettings?.PRODUCT_NAME) {
        entry.buildSettings.SWIFT_ACTIVE_COMPILATION_CONDITIONS = `"$(inherited) ${FLAG}"`;
      }
    }
    return next;
  });
