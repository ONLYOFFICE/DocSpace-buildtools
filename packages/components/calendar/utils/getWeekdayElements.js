import { Weekday } from "../styled-components";
import moment from "moment";

export const getWeekdayElements = () => {
  const weekdays = moment
    .weekdaysMin(true)
    .map((weekday) => weekday.charAt(0).toUpperCase() + weekday.substring(1));
  return weekdays.map((day) => <Weekday key={day}>{day}</Weekday>);
};