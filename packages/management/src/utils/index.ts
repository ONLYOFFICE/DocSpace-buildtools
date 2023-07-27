import { settingsTree } from "./settingsTree"
import { translations } from "../autoGeneratedTranslations";

export const getItemByLink = (path: string) => {
    const resultPath = path.split("/")[2];
    const item = settingsTree.filter((item) => item.link === resultPath);
    return item[0];
}

export function getLanguage(lng: string) {
    try {
        let language = lng == "en-US" || lng == "en-GB" ? "en" : lng;

        const splitted = lng.split("-");

        if (splitted.length == 2 && splitted[0] == splitted[1].toLowerCase()) {
            language = splitted[0];
        }

        return language;
    } catch (error) {
        console.error(error);
    }

    return lng;
}

export function loadLanguagePath(homepage: string, fixedNS = null) {
    return (lng: string | [string], ns: string) => {
        const language = getLanguage(lng instanceof Array ? lng[0] : lng);

        const lngCollection = translations.get(language);

        const path = lngCollection?.get(`${fixedNS || ns}`);

        if (!path) return `/management/locales/${language}/${fixedNS || ns}.json`;

        const isCommonPath = path?.indexOf("Common") > -1;
        const isClientPath = !isCommonPath && path?.indexOf("Management") === -1;

        if (ns.length > 0 && ns[0] === "Common" && isCommonPath) {
            return path.replace("/management/", "/static/");
        }

        if (ns.length > 0 && ns[0] != "Management" && isClientPath) {
            return path.replace("/management/", "/");
        }

        return path;
    };
}