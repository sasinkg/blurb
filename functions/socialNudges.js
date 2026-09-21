const TIME_ZONE = "America/Los_Angeles";

function localDateKey(date, timeZone = TIME_ZONE) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    timeZone,
  }).formatToParts(date);
  const value = (type) => parts.find((part) => part.type === type)?.value;
  return `${value("year")}-${value("month")}-${value("day")}`;
}

function unansweredMemberIDs({memberIDs, senderID, answeredAuthorIDs}) {
  const answered = new Set(answeredAuthorIDs);
  return [...new Set(memberIDs)].filter((userID) => userID !== senderID && !answered.has(userID));
}

module.exports = {localDateKey, unansweredMemberIDs};
