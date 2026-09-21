const {onDocumentCreated, onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();

const {notificationRecipients} = require("./mentions");
const {
  buildSelection,
  photoMonthKey,
  selectionDocumentID,
  validateSelectionInput,
} = require("./photoOfMonth");

exports.setPhotoOfMonthSelection = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in to choose a photo.");

  let input;
  try {
    input = validateSelectionInput(request.data);
  } catch (error) {
    throw new HttpsError("invalid-argument", error.message);
  }

  const database = getFirestore();
  const userID = request.auth.uid;
  const groupSnapshot = await database.doc(`groups/${input.groupID}`).get();
  const group = groupSnapshot.data();
  if (!groupSnapshot.exists || !(group.memberIDs ?? []).includes(userID)) {
    throw new HttpsError("permission-denied", "You are not a member of this group.");
  }

  const postSnapshot = await database.doc(`posts/${input.postID}`).get();
  const post = postSnapshot.data();
  if (!postSnapshot.exists || post.groupID !== input.groupID || post.authorID !== userID) {
    throw new HttpsError("permission-denied", "Choose one of your own Blurbs from this group.");
  }
  if (typeof post.imageURL !== "string" || !post.imageURL) {
    throw new HttpsError("failed-precondition", "The selected Blurb does not have a photo.");
  }

  const createdAt = post.createdAt?.toDate?.();
  const monthKey = photoMonthKey(new Date());
  if (!createdAt || photoMonthKey(createdAt) !== monthKey) {
    throw new HttpsError("failed-precondition", "Choose a photo posted during the current month.");
  }

  const reference = database.doc(
      `users/${userID}/photoOfMonthSelections/${selectionDocumentID(input.groupID, monthKey)}`,
  );
  await database.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    const selection = {
      ...buildSelection({groupID: input.groupID, postID: input.postID, post, userID, monthKey}),
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (!existing.exists) selection.createdAt = FieldValue.serverTimestamp();
    transaction.set(reference, selection, {merge: true});
  });

  return {monthKey, postID: input.postID};
});

async function notifyGroupActivity({eventID, postID, post, senderID, text, previousText = "", commentID}) {
  if (!post || post.isSample || !post.groupID || !senderID) return;
  const database = getFirestore();
  const group = (await database.doc(`groups/${post.groupID}`).get()).data();
  const memberIDs = [...new Set(group?.memberIDs ?? [])];
  if (!memberIDs.includes(senderID)) return;
  const snapshots = await Promise.all(memberIDs.map((id) => database.doc(`users/${id}`).get()));
  const members = snapshots.filter((snapshot) => snapshot.exists)
      .map((snapshot) => ({...snapshot.data(), id: snapshot.id}));
  const sender = members.find((member) => member.id === senderID);
  const recipients = notificationRecipients({text, members, senderID, previousText,
    postAuthorID: commentID ? post.authorID : undefined});
  for (const [userID, type] of recipients) {
    const member = members.find((entry) => entry.id === userID);
    const tokens = [...new Set(member?.fcmTokens ?? [])].filter((token) => typeof token === "string" && token);
    if (!tokens.length) continue;
    const receiptID = Buffer.from(`${eventID}:${userID}`).toString("base64url");
    const receipt = database.collection("notificationDeliveries").doc(receiptID);
    const claimed = await database.runTransaction(async (transaction) => {
      if ((await transaction.get(receipt)).exists) return false;
      transaction.create(receipt, {createdAt: FieldValue.serverTimestamp()});
      return true;
    });
    if (!claimed) continue;
    // At-most-once claim avoids duplicate pushes from duplicate Firestore events.
    // Keep answer text out of notifications so the answer-first gate is preserved.
    for (let offset = 0; offset < tokens.length; offset += 500) {
      const batch = tokens.slice(offset, offset + 500);
      const response = await getMessaging().sendEachForMulticast({
        tokens: batch,
        notification: {
          title: type === "mention" ? `${sender?.displayName ?? "Someone"} mentioned you` : `${sender?.displayName ?? "Someone"} replied to your answer`,
          body: type === "mention" ? `You were mentioned in ${commentID ? "a reply" : "an answer"} in ${group.name ?? "your group"}.` : `Open ${group.name ?? "your group"} to read the reply.`,
        },
        data: {postID, groupID: post.groupID, type, ...(commentID ? {commentID} : {})},
        apns: {payload: {aps: {sound: "default"}}},
      });
      const invalid = batch.filter((_, index) => ["messaging/invalid-registration-token", "messaging/registration-token-not-registered"].includes(response.responses[index].error?.code));
      if (invalid.length) await database.doc(`users/${userID}`).update({fcmTokens: FieldValue.arrayRemove(...invalid)});
    }
  }
}

exports.notifyAnswerReply = onDocumentCreated("posts/{postID}/comments/{commentID}", async (event) => {
  const comment = event.data?.data();
  if (!comment) return;
  const post = (await getFirestore().doc(`posts/${event.params.postID}`).get()).data();
  await notifyGroupActivity({eventID: event.id, postID: event.params.postID, post,
    senderID: comment.authorID, text: comment.text, commentID: event.params.commentID});
});

exports.notifyAnswerMentions = onDocumentWritten("posts/{postID}", async (event) => {
  const post = event.data?.after.data();
  const previous = event.data?.before.data();
  if (!post || previous?.answer === post.answer) return;
  await notifyGroupActivity({eventID: event.id, postID: event.params.postID, post,
    senderID: post.authorID, text: post.answer, previousText: previous?.answer ?? ""});
});

exports.generateMonthlyNewsletters = onSchedule(
    {schedule: "0 8 3 * *", timeZone: "America/Los_Angeles"},
    async () => {
      const database = getFirestore();
      const now = new Date();
      const target = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 15));
      const monthKey = `${target.getUTCFullYear()}-${String(target.getUTCMonth() + 1).padStart(2, "0")}`;
      const monthLabel = target.toLocaleDateString("en-US", {month: "long", year: "numeric", timeZone: "UTC"});
      const groups = await database.collection("groups").get();

      for (const groupDocument of groups.docs) {
        const group = groupDocument.data();
        const postsSnapshot = await database.collection("posts")
            .where("groupID", "==", groupDocument.id)
            .get();
        const monthPosts = postsSnapshot.docs.filter((document) => {
          const createdAt = document.data().createdAt?.toDate?.();
          if (!createdAt) return false;
          const parts = new Intl.DateTimeFormat("en-US", {
            year: "numeric", month: "2-digit", timeZone: "America/Los_Angeles",
          }).formatToParts(createdAt);
          const postMonth = `${parts.find((part) => part.type === "year").value}-${parts.find((part) => part.type === "month").value}`;
          return postMonth === monthKey;
        });

        if (monthPosts.length === 0) continue;
        const totals = {};
        const counts = {};
        const entries = [];
        let photoCount = 0;
        let mostLiked = null;
        let mostCommented = null;
        for (const document of monthPosts) {
          const post = document.data();
          totals[post.authorName] = (totals[post.authorName] ?? 0) + (post.pointsAwarded ?? 0);
          counts[post.authorName] = (counts[post.authorName] ?? 0) + 1;
          if (post.imageURL) photoCount += 1;
          const summary = {postID: document.id, authorName: post.authorName, prompt: post.prompt ?? "", answer: post.answer ?? "", value: 0};
          const likes = Array.isArray(post.likeIDs) ? post.likeIDs.length : 0;
          const comments = post.commentCount ?? 0;
          if (!mostLiked || likes > mostLiked.value) mostLiked = {...summary, value: likes};
          if (!mostCommented || comments > mostCommented.value) mostCommented = {...summary, value: comments};
          entries.push({
            postID: document.id,
            authorID: post.authorID,
            authorName: post.authorName,
            authorPhotoURL: post.authorPhotoURL ?? null,
            answer: post.answer ?? "",
            prompt: post.prompt ?? "",
            promptID: post.promptID ?? "",
            imageURL: post.imageURL ?? null,
            pollOptions: post.pollOptions ?? [],
            createdAt: post.createdAt,
            pointsAwarded: post.pointsAwarded ?? 0,
          });
        }

        for (const userID of group.memberIDs ?? []) {
          const selectionID = selectionDocumentID(groupDocument.id, monthKey);
          const selection = (await database.doc(`users/${userID}/photoOfMonthSelections/${selectionID}`).get()).data();
          if (selection?.imageURL) {
            entries.push({
              postID: `photo-of-month-${userID}-${monthKey}`,
              sourcePostID: selection.postID,
              authorID: userID,
              authorName: selection.authorName ?? "Blurb friend",
              answer: "",
              prompt: "Photo of the Month",
              promptID: `photo-of-month-${monthKey}`,
              imageURL: selection.imageURL,
              pollOptions: [],
              createdAt: selection.postCreatedAt,
              pointsAwarded: 0,
              isPhotoOfMonth: true,
            });
          }
        }

        const mostAnswers = Object.entries(counts).sort((a, b) => b[1] - a[1])[0] ?? null;
        const mostPoints = Object.entries(totals).sort((a, b) => b[1] - a[1])[0] ?? null;
        await database.collection("newsletterEditions")
            .doc(`${groupDocument.id}_${monthKey}`)
            .set({
              groupID: groupDocument.id,
              groupName: group.name,
              viewerIDs: group.memberIDs ?? [],
              monthKey,
              monthLabel,
              generatedAt: FieldValue.serverTimestamp(),
              entries,
              winners: {
                mostAnswers: mostAnswers ? {name: mostAnswers[0], value: mostAnswers[1]} : null,
                mostPoints: mostPoints ? {name: mostPoints[0], value: mostPoints[1]} : null,
              },
              stats: {
                answerCount: monthPosts.length,
                questionCount: new Set(monthPosts.map((document) => document.data().promptID)).size,
                photoCount,
                participatingMemberCount: Object.keys(counts).length,
                groupMemberCount: (group.memberIDs ?? []).length,
                mostLiked,
                mostCommented,
              },
            });
      }
    },
);

exports.remindPhotoOfMonth = onSchedule(
    {schedule: "0 18 28 * *", timeZone: "America/Los_Angeles"},
    async () => {
      const database = getFirestore();
      const monthKey = photoMonthKey(new Date());
      const groups = await database.collection("groups").get();
      for (const groupDocument of groups.docs) {
        const group = groupDocument.data();
        for (const userID of group.memberIDs ?? []) {
          const selectionID = selectionDocumentID(groupDocument.id, monthKey);
          if ((await database.doc(`users/${userID}/photoOfMonthSelections/${selectionID}`).get()).exists) continue;
          const receipt = database.doc(`notificationDeliveries/photo-month-${groupDocument.id}-${userID}-${monthKey}`);
          const claimed = await database.runTransaction(async (transaction) => {
            if ((await transaction.get(receipt)).exists) return false;
            transaction.create(receipt, {createdAt: FieldValue.serverTimestamp()});
            return true;
          });
          if (!claimed) continue;
          const user = (await database.doc(`users/${userID}`).get()).data();
          const tokens = [...new Set(user?.fcmTokens ?? [])].filter(Boolean);
          if (tokens.length) await getMessaging().sendEachForMulticast({
            tokens,
            notification: {title: "Choose your Photo of the Month", body: `Pick one photo for ${group.name ?? "your group"} before the month ends.`},
            data: {type: "photoOfMonth", groupID: groupDocument.id},
            apns: {payload: {aps: {sound: "default"}}},
          });
        }
      }
    },
);
