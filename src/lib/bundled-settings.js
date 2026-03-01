const DEFAULT_PROFILE_ID = '*gen_grbl';

const SETTINGS_BUNDLE = require('../../Settings/laserweb-settings.json');
const PROFILES_BUNDLE = require('../../Settings/laserweb-profiles.json');

export const resolveBundledSettings = () => {
    if (SETTINGS_BUNDLE && SETTINGS_BUNDLE.settings) return SETTINGS_BUNDLE.settings;
    return SETTINGS_BUNDLE || null;
};

export const resolveBundledProfiles = () => {
    if (PROFILES_BUNDLE && PROFILES_BUNDLE.machineProfiles) return PROFILES_BUNDLE.machineProfiles;
    return PROFILES_BUNDLE || null;
};

export const resolveDefaultProfileId = (profiles) => {
    if (!profiles) return null;
    if (profiles[DEFAULT_PROFILE_ID]) return DEFAULT_PROFILE_ID;
    const lockedProfile = Object.keys(profiles).find((id) => /^\*/.test(id));
    if (lockedProfile) return lockedProfile;
    return Object.keys(profiles)[0] || null;
};

const getLockedProfiles = (profiles) => {
    return Object.entries(profiles || {}).reduce((lockedProfiles, [id, profile]) => {
        if (/^\*/.test(id)) lockedProfiles[id] = profile;
        return lockedProfiles;
    }, {});
};

export const buildBundledState = (state, { applySettings = false, resetProfiles = false } = {}) => {
    const bundledProfiles = resolveBundledProfiles() || {};
    const currentProfiles = resetProfiles ? getLockedProfiles(state.machineProfiles) : (state.machineProfiles || {});
    const machineProfiles = { ...bundledProfiles, ...currentProfiles };

    if (!applySettings) {
        return { ...state, machineProfiles };
    }

    const bundledSettings = resolveBundledSettings();
    let settings = { ...(state.settings || {}), ...(bundledSettings || {}) };

    const selectedProfileId = settings && settings.__selectedProfile;
    const selectedProfile = selectedProfileId && machineProfiles[selectedProfileId];
    if (selectedProfile && selectedProfile.settings) {
        settings = { ...settings, ...selectedProfile.settings, __selectedProfile: selectedProfileId };
    } else {
        const defaultProfileId = resolveDefaultProfileId(machineProfiles);
        const defaultProfile = defaultProfileId ? machineProfiles[defaultProfileId] : null;
        if (defaultProfile && defaultProfile.settings) {
            settings = { ...settings, ...defaultProfile.settings, __selectedProfile: defaultProfileId };
        }
    }

    return { ...state, machineProfiles, settings };
};
