const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();

exports.notifyAnswerReply = onDocumentCreated(
    "posts/{postID}/comments/{commentID}",
    async (event) => {
      const comment = event.data?.data();
      if (!comment) return;

      const database = getFirestore();
      const postSnapshot = await database.doc(`posts/${event.params.postID}`).get();
      const post = postSnapshot.data();
      if (!post || post.authorID === comment.authorID) return;

      const userReference = database.doc(`users/${post.authorID}`);
      const userSnapshot = await userReference.get();
      const tokens = userSnapshot.data()?.fcmTokens ?? [];
      if (tokens.length === 0) return;

      const reply = String(comment.text ?? "").trim();
      const body = reply.length > 120 ? `${reply.slice(0, 117)}…` : reply;
      const response = await getMessaging().sendEachForMulticast({
        tokens,
        notification: {
          title: `${comment.authorName ?? "Someone"} replied to your answer`,
          body,
        },
        data: {
          postID: event.params.postID,
          type: "answerReply",
        },
        apns: {
          payload: {aps: {sound: "default"}},
        },
      });

      const invalidTokens = [];
      response.responses.forEach((result, index) => {
        if (!result.success && [
          "messaging/invalid-registration-token",
          "messaging/registration-token-not-registered",
        ].includes(result.error?.code)) {
          invalidTokens.push(tokens[index]);
        }
      });
      if (invalidTokens.length > 0) {
        await userReference.update({fcmTokens: FieldValue.arrayRemove(...invalidTokens)});
      }
    },
);

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
        for (const document of monthPosts) {
          const post = document.data();
          totals[post.authorName] = (totals[post.authorName] ?? 0) + (post.pointsAwarded ?? 0);
          counts[post.authorName] = (counts[post.authorName] ?? 0) + 1;
          if (post.isMonthlyReportPrompt === true || post.imageURL) {
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
            });
      }
    },
);
