const TIME_ZONE = "America/Los_Angeles";

function dateParts(date, timeZone = TIME_ZONE) {
  const parts = new Intl.DateTimeFormat("en-US", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    timeZone,
  }).formatToParts(date);
  const value = (type) => Number(parts.find((part) => part.type === type)?.value);
  return {year: value("year"), month: value("month"), day: value("day")};
}

// The app treats midnight through 4:59 a.m. Pacific as the previous content day.
function newsletterContext(date, timeZone = TIME_ZONE) {
  const contentDate = new Date(date.getTime() - (5 * 60 * 60 * 1000));
  const {year, month, day} = dateParts(contentDate, timeZone);
  const firstWeekday = new Date(Date.UTC(year, month - 1, 1)).getUTCDay();
  const firstFriday = 1 + ((5 - firstWeekday + 7) % 7);
  const releasedCount = day < firstFriday ? 0 : Math.min(4, Math.floor((day - firstFriday) / 7) + 1);
  return {
    releasedCount,
    promptIDs: Array.from({length: releasedCount}, (_, index) =>
      `newsletter-${year}-${month}-${index + 1}`),
  };
}

function memberQuestionCounts(posts, memberIDs, releasedPromptIDs) {
  const released = new Set(releasedPromptIDs);
  const answered = new Map(memberIDs.map((id) => [id, new Set()]));
  for (const post of posts) {
    if (post?.isSample || !answered.has(post?.authorID) || !released.has(post?.promptID)) continue;
    answered.get(post.authorID).add(post.promptID);
  }
  return new Map([...answered].map(([id, promptIDs]) => [id, promptIDs.size]));
}

function nudgeMessage({senderName, groupName, needsQuestions, needsPhoto}) {
  const title = `${senderName || "Your group manager"} sent a nudge`;
  let task = "finish your monthly check-in";
  if (needsQuestions && needsPhoto) task = "finish this month’s questions and choose your Photo of the Month";
  else if (needsQuestions) task = "finish this month’s newsletter questions";
  else if (needsPhoto) task = "choose your Photo of the Month";
  return {title, body: `${task[0].toUpperCase()}${task.slice(1)} in ${groupName || "your group"}.`};
}

module.exports = {memberQuestionCounts, newsletterContext, nudgeMessage};
