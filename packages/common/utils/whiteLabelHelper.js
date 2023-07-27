import axios from "axios";
import isEqual from "lodash/isEqual";

export const generateLogo = (
  width,
  height,
  text,
  fontSize = 18,
  fontColor = "#000",
  isEditorLogo = false
) => {
  const canvas = document.createElement("canvas");
  canvas.width = isEditorLogo ? "154" : width;
  canvas.height = isEditorLogo ? "27" : height;
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = "transparent";
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = fontColor;
  ctx.textAlign = "start";
  ctx.textBaseline = "top";
  ctx.font = `${fontSize}px Arial`;
  ctx.fillText(text, 0, height / 2 - fontSize / 2);

  return canvas.toDataURL();
};

export const getLogoOptions = (index, text) => {
  switch (index) {
    case 0:
      return { fontSize: 18, text: text };
    case 1:
      return { fontSize: 44, text: text };
    case 2:
      return { fontSize: 16, text: text.trim().charAt(0) };
    case 3:
      return { fontSize: 16, text: text, isEditorLogo: true };
    case 4:
      return { fontSize: 16, text: text, isEditorLogo: true };
    case 5:
      return { fontSize: 30, text: text.trim().charAt(0) };
    case 6:
      return { fontSize: 32, text: text };
    default:
      return { fontSize: 18, text: text };
  }
};

export const uploadLogo = async (file) => {
  try {
    const { width, height } = await getUploadedFileDimensions(file);
    let data = new FormData();
    data.append("file", file);
    data.append("width", width);
    data.append("height", height);

    return await axios.post("/logoUploader.ashx", data);
  } catch (error) {
    console.error(error);
  }
};

const getUploadedFileDimensions = (file) =>
  new Promise((resolve, reject) => {
    try {
      let img = new Image();

      img.onload = () => {
        const width = img.naturalWidth,
          height = img.naturalHeight;

        window.URL.revokeObjectURL(img.src);

        return resolve({ width, height });
      };

      img.src = window.URL.createObjectURL(file);
    } catch (exception) {
      return reject(exception);
    }
  });

export const getNewLogoArr = (
  logoUrlsWhiteLabel,
  defaultWhiteLabelLogoUrls
) => {
  let logosArr = [];

  for (let i = 0; i < logoUrlsWhiteLabel.length; i++) {
    const currentLogo = logoUrlsWhiteLabel[i];
    const defaultLogo = defaultWhiteLabelLogoUrls[i];

    if (!isEqual(currentLogo, defaultLogo)) {
      let value = {};

      if (!isEqual(currentLogo.path.light, defaultLogo.path.light))
        value.light = currentLogo.path.light;
      if (!isEqual(currentLogo.path.dark, defaultLogo.path.dark))
        value.dark = currentLogo.path.dark;

      logosArr.push({
        key: String(i + 1),
        value: value,
      });
    }
  }
  return logosArr;
};

export const getLogosAsText = (logoUrlsWhiteLabel, logoTextWhiteLabel) => {
  let newLogos = logoUrlsWhiteLabel;
  for (let i = 0; i < logoUrlsWhiteLabel.length; i++) {
    const width = logoUrlsWhiteLabel[i].size.width / 2;
    const height = logoUrlsWhiteLabel[i].size.height / 2;
    const options = getLogoOptions(i, logoTextWhiteLabel);
    const isDocsEditorName = logoUrlsWhiteLabel[i].name === "DocsEditor";

    const logoLight = generateLogo(
      width,
      height,
      options.text,
      options.fontSize,
      isDocsEditorName ? "#fff" : "#000",
      options.isEditorLogo
    );
    const logoDark = generateLogo(
      width,
      height,
      options.text,
      options.fontSize,
      "#fff",
      options.isEditorLogo
    );
    newLogos[i].path.light = logoLight;
    newLogos[i].path.dark = logoDark;
  }
  return newLogos;
};