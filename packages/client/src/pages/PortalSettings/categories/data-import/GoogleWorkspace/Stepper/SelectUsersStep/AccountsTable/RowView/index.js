import { useEffect, useRef } from "react";
import { inject, observer } from "mobx-react";
import { isMobile } from "react-device-detect";
import { tablet } from "@docspace/components/utils/device";
import styled from "styled-components";

import EmptyScreenContainer from "@docspace/components/empty-screen-container";
import IconButton from "@docspace/components/icon-button";
import Link from "@docspace/components/link";
import Box from "@docspace/components/box";
import RowContainer from "@docspace/components/row-container";
import Row from "@docspace/components/row";
import Checkbox from "@docspace/components/checkbox";
import Text from "@docspace/components/text";
import UsersRow from "./UsersRow";
import EmptyScreenUserReactSvgUrl from "PUBLIC_DIR/images/empty_screen_user.react.svg?url";
import ClearEmptyFilterSvgUrl from "PUBLIC_DIR/images/clear.empty.filter.svg?url";

const StyledRowContainer = styled(RowContainer)`
  margin: 0 0 20px;

  .clear-icon {
    margin-right: 8px;
  }

  .ec-desc {
    max-width: 348px;
  }
`;

const StyledRow = styled(Row)`
  box-sizing: border-box;
  height: 40px;
  min-height: 40px;

  .row-header-item {
    display: flex;
    align-items: center;
    margin-left: 7px;
  }

  .row-header-title {
    color: ${(props) => props.theme.client.settings.migration.tableHeaderText};
    font-weight: 600;
    font-size: 12px;
  }

  @media ${tablet} {
    .row_content {
      height: auto;
    }
  }
`;

const RowView = (props) => {
  const {
    t,
    users,
    sectionWidth,
    viewAs,
    setViewAs,
    accountsData,
    checkedAccounts,
    toggleAccount,
    toggleAllAccounts,
    isAccountChecked,
    setSearchValue,
  } = props;
  const rowRef = useRef(null);

  const toggleAll = (e) => toggleAllAccounts(e, users);

  const handleToggle = (id) => toggleAccount(id);

  const onClearFilter = () => {
    setSearchValue("");
  };

  const isIndeterminate =
    checkedAccounts.length > 0 && checkedAccounts.length !== users.length;

  useEffect(() => {
    if (viewAs !== "table" && viewAs !== "row") return;

    if (sectionWidth < 1025 || isMobile) {
      viewAs !== "row" && setViewAs("row");
    } else {
      viewAs !== "table" && setViewAs("table");
    }
  }, [sectionWidth]);

  return (
    <StyledRowContainer forwardedRef={rowRef} useReactWindow={false}>
      {accountsData.length > 0 ? (
        <>
          <StyledRow sectionWidth={sectionWidth}>
            <div className="row-header-item">
              {checkedAccounts.length > 0 && (
                <Checkbox
                  isChecked={checkedAccounts.length === users.length}
                  isIndeterminate={isIndeterminate}
                  onChange={toggleAll}
                />
              )}
              <Text className="row-header-title">{t("Common:Name")}</Text>
            </div>
          </StyledRow>
          {accountsData.map((data) => (
            <UsersRow
              t={t}
              key={data.key}
              data={data}
              sectionWidth={sectionWidth}
              isChecked={isAccountChecked(data.key)}
              toggleAccount={() => handleToggle(data.key)}
            />
          ))}
        </>
      ) : (
        <EmptyScreenContainer
          imageSrc={EmptyScreenUserReactSvgUrl}
          imageAlt="Empty Screen user image"
          headerText={t("People:NotFoundUsers")}
          descriptionText={t("People:NotFoundUsersDesc")}
          buttons={
            <Box displayProp="flex" alignItems="center">
              <IconButton
                className="clear-icon"
                isFill
                size="12"
                onClick={onClearFilter}
                iconName={ClearEmptyFilterSvgUrl}
              />
              <Link
                type="action"
                isHovered={true}
                fontWeight="600"
                onClick={onClearFilter}
              >
                {t("Common:ClearFilter")}
              </Link>
            </Box>
          }
        />
      )}
    </StyledRowContainer>
  );
};

export default inject(({ setup, importAccountsStore }) => {
  const { viewAs, setViewAs } = setup;
  const {
    users,
    checkedAccounts,
    toggleAccount,
    toggleAllAccounts,
    isAccountChecked,
    setSearchValue,
  } = importAccountsStore;

  return {
    users,
    viewAs,
    setViewAs,
    checkedAccounts,
    toggleAccount,
    toggleAllAccounts,
    isAccountChecked,
    setSearchValue,
  };
})(observer(RowView));