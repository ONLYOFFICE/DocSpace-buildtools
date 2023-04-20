import React from "react";
import { inject, observer } from "mobx-react";
import { useLocation, Navigate, Route, Outlet } from "react-router-dom";
import { withTranslation } from "react-i18next";

import Article from "@docspace/common/components/Article";
import {
  updateTempContent,
  loadScript,
  showLoader,
  hideLoader,
} from "@docspace/common/utils";
import { regDesktop } from "@docspace/common/desktop";

import toastr from "@docspace/components/toast/toastr";

import FilesPanels from "./components/FilesPanels";
import GlobalEvents from "./components/GlobalEvents";
import {
  ArticleBodyContent,
  ArticleHeaderContent,
  ArticleMainButtonContent,
} from "./components/Article";

const ClientArticle = React.memo(({ withMainButton }) => {
  return (
    <Article withMainButton={withMainButton}>
      <Article.Header>
        <ArticleHeaderContent />
      </Article.Header>

      <Article.MainButton>
        <ArticleMainButtonContent />
      </Article.MainButton>

      <Article.Body>
        <ArticleBodyContent />
      </Article.Body>
    </Article>
  );
});

const ClientContent = (props) => {
  const {
    loadClientInfo,
    setIsLoaded,
    isAuthenticated,
    user,
    isEncryption,
    encryptionKeys,
    setEncryptionKeys,
    isLoaded,
    isDesktop,
    showMenu,
    isFrame,
    withMainButton,
    t,
    setFirstLoad,
    isLoading,
  } = props;

  const location = useLocation();

  const isEditor = location.pathname.indexOf("doceditor") !== -1;
  const isFormGallery = location.pathname.split("/").includes("form-gallery");

  const [isDesktopInit, setIsDesktopInit] = React.useState(false);

  React.useEffect(() => {
    loadScript("/static/scripts/tiff.min.js", "img-tiff-script");

    loadClientInfo()
      .catch((err) => toastr.error(err))
      .finally(() => {
        setIsLoaded(true);

        updateTempContent();
      });

    return () => {
      const script = document.getElementById("img-tiff-script");
      document.body.removeChild(script);
    };
  }, []);

  React.useEffect(() => {
    if (isAuthenticated && !isDesktopInit && isDesktop && isLoaded) {
      setIsDesktopInit(true);
      regDesktop(
        user,
        isEncryption,
        encryptionKeys,
        setEncryptionKeys,
        isEditor,
        null,
        t
      );
      //   console.log(
      //     "%c%s",
      //     "color: green; font: 1.2em bold;",
      //     "Current keys is: ",
      //     encryptionKeys
      //   );
    }
  }, [
    t,
    isAuthenticated,
    user,
    isEncryption,
    encryptionKeys,
    setEncryptionKeys,
    isLoaded,
    isDesktop,
    isDesktopInit,
  ]);

  React.useEffect(() => {
    setFirstLoad(false);
  }, [setFirstLoad]);

  React.useEffect(() => {
    if (isLoading) {
      showLoader();
    } else {
      hideLoader();
    }
  }, [isLoading]);

  return (
    <>
      <GlobalEvents />
      <FilesPanels />
      {!isFormGallery ? (
        isFrame ? (
          showMenu && <ClientArticle />
        ) : (
          <ClientArticle withMainButton={withMainButton} />
        )
      ) : (
        <></>
      )}
      <Outlet />
    </>
  );
};

const Client = inject(({ auth, filesStore, peopleStore }) => {
  const {
    frameConfig,
    isFrame,
    isDesktopClient,
    encryptionKeys,
    setEncryptionKeys,
    isEncryptionSupport,
  } = auth.settingsStore;

  if (!auth.userStore.user) return;

  const { isVisitor } = auth.userStore.user;

  const { setFirstLoad, isLoading } = filesStore;

  const withMainButton = !isVisitor;

  return {
    isDesktop: isDesktopClient,
    isFrame,
    showMenu: frameConfig?.showMenu,
    user: auth.userStore.user,
    isAuthenticated: auth.isAuthenticated,
    encryptionKeys: encryptionKeys,
    isEncryption: isEncryptionSupport,
    isLoaded: auth.isLoaded && filesStore.isLoaded,
    setIsLoaded: filesStore.setIsLoaded,
    withMainButton,
    setFirstLoad,
    isLoading,
    setEncryptionKeys: setEncryptionKeys,
    loadClientInfo: async () => {
      const actions = [];
      actions.push(filesStore.initFiles());
      actions.push(peopleStore.init());
      await Promise.all(actions);
    },
  };
})(withTranslation("Common")(observer(ClientContent)));

export default () => <Client />;