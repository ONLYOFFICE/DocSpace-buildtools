import styled from "styled-components";
import Text from "@docspace/components/text";
import Box from "@docspace/components/box";
import RowContent from "@docspace/components/row-content";

const StyledRowContent = styled(RowContent)`
  display: flex;

  .rowMainContainer {
    height: 100%;
    width: 100%;
  }

  .username {
    font-size: 14px;
    font-weight: 600;
    color: ${(props) => props.theme.client.settings.migration.subtitleColor};
  }

  .user-email {
    margin-right: 5px;
    font-size: 12px;
    font-weight: 600;
    color: ${(props) =>
      props.theme.client.settings.migration.tableRowTextColor};
  }

  .user-existing {
    font-size: 12px;
    font-weight: 600;
    color: ${(props) =>
      props.theme.client.settings.migration.existingTextColor};
  }
`;

const UsersRowContent = ({
  t,
  sectionWidth,
  displayName,
  email,
  isDublicate,
}) => {
  const contentData = [
    <>
      <Text className="username">{displayName}</Text>
      <Box displayProp="flex">
        <Text className="user-email">{email}</Text>
        {isDublicate && (
          <Text className="user-existing">{t("Settings:ExistingAccount")}</Text>
        )}
      </Box>
    </>,
  ];

  return (
    <StyledRowContent sectionWidth={sectionWidth}>
      {contentData}
    </StyledRowContent>
  );
};

export default UsersRowContent;