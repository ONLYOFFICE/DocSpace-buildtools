import React, { useEffect } from "react";
import { useTranslation } from "react-i18next";
import { inject, observer } from "mobx-react";

import Section from "@docspace/common/components/Section";

import SectionBodyContent from "./Section/Body/index";
import SectionHeaderContent from "./Section/Header/index";

const NotificationComponent = (props) => {
  const { setSelectedNode, setFirstLoad } = props;
  const { t, ready } = useTranslation("Notifications");

  useEffect(() => {
    setFirstLoad(false);
    setSelectedNode(["accounts"]);
  }, []);

  return (
    <Section>
      <Section.SectionHeader>
        <SectionHeaderContent t={t} />
      </Section.SectionHeader>

      <Section.SectionBody>
        <SectionBodyContent t={t} ready={ready} />
      </Section.SectionBody>
    </Section>
  );
};

export default inject(({ treeFoldersStore, filesStore }) => {
  const { setSelectedNode } = treeFoldersStore;
  const { setFirstLoad } = filesStore;
  return {
    setFirstLoad,
    setSelectedNode,
  };
})(observer(NotificationComponent));