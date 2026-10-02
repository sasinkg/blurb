const {onDocumentCreated, onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const {SignedDataVerifier, Environment} = require("@apple/app-store-server-library");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {getStorage, getDownloadURL} = require("firebase-admin/storage");

initializeApp();

const {notificationRecipients} = require("./mentions");
const {localDateKey, unansweredMemberIDs} = require("./socialNudges");
const {aggregateCities, normalizeCityLocation} = require("./cityLocations");
const {memberQuestionCounts, newsletterContext, nudgeMessage} = require("./monthlyProgress");
const {
  buildSelection,
  photoMonthKey,
  selectionDocumentID,
  validateCaption,
  validateSelectionInput,
  validPrivatePhotoPath,
} = require("./photoOfMonth");
const {songDisplayText, validateSongSelectionInput} = require("./songOfMonth");

const premiumProductID = "sasinkg.blurb.group.premium.monthly";
const appBundleID = "sasinkg.blurb";
const appAppleID = 6812228458;
const appleRoots = [
  "AppleIncRootCertificate.cer",
  "AppleRootCA-G2.cer",
  "AppleRootCA-G3.cer",
].map((name) => fs.readFileSync(path.join(__dirname, "apple-certs", name)));
const productionVerifier = new SignedDataVerifier(appleRoots, true, Environment.PRODUCTION, appBundleID, appAppleID);
const sandboxVerifier = new SignedDataVerifier(appleRoots, true, Environment.SANDBOX, appBundleID);

function accountTokenFor(userID) {
  const bytes = Buffer.from(crypto.createHash("sha256").update(userID).digest().subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

async function verifyAppStoreTransaction(signedTransaction) {
  try {
    return {transaction: await productionVerifier.verifyAndDecodeTransaction(signedTransaction), environment: "production"};
  } catch (productionError) {
    try {
      return {transaction: await sandboxVerifier.verifyAndDecodeTransaction(signedTransaction), environment: "sandbox"};
    } catch (sandboxError) {
      console.error("App Store transaction verification failed", productionError, sandboxError);
      throw new HttpsError("permission-denied", "The App Store purchase could not be verified.");
    }
  }
}

function premiumIsActive(group) {
  const expiresAt = group?.premium?.expiresAt;
  return group?.premium?.status === "active" && expiresAt?.toMillis?.() > Date.now();
}

async function requirePremiumMember(database, groupID, userID) {
  const snapshot = await database.doc(`groups/${groupID}`).get();
  const group = snapshot.data();
  if (!snapshot.exists || !(group?.memberIDs ?? []).includes(userID)) {
    throw new HttpsError("permission-denied", "You must be a member of this group.");
  }
  if (!premiumIsActive(group)) {
    throw new HttpsError("failed-precondition", "This group needs Blurb Premium.");
  }
  return {snapshot, group};
}

exports.activateGroupPremium = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in to activate Premium.");
  const groupID = typeof request.data?.groupID === "string" ? request.data.groupID.trim() : "";
  const signedTransaction = typeof request.data?.signedTransaction === "string" ? request.data.signedTransaction : "";
  if (!groupID || !signedTransaction) throw new HttpsError("invalid-argument", "A group and purchase are required.");

  const database = getFirestore();
  const groupReference = database.doc(`groups/${groupID}`);
  const groupSnapshot = await groupReference.get();
  const group = groupSnapshot.data();
  if (!groupSnapshot.exists || !(group?.memberIDs ?? []).includes(request.auth.uid)) {
    throw new HttpsError("permission-denied", "You must be a member of this group.");
  }

  const verified = await verifyAppStoreTransaction(signedTransaction);
  const transaction = verified.transaction;
  if (transaction.productId !== premiumProductID || !transaction.originalTransactionId || !transaction.expiresDate) {
    throw new HttpsError("invalid-argument", "This purchase is not a Blurb Premium subscription.");
  }
  if (transaction.appAccountToken?.toLowerCase() !== accountTokenFor(request.auth.uid) || transaction.revocationDate) {
    throw new HttpsError("permission-denied", "This purchase does not belong to the signed-in Blurb account.");
  }
  if (transaction.expiresDate <= Date.now()) {
    throw new HttpsError("failed-precondition", "This subscription has expired.");
  }

  const transactionReference = database.doc(`premiumTransactions/${transaction.originalTransactionId}`);
  await database.runTransaction(async (firestoreTransaction) => {
    const existing = await firestoreTransaction.get(transactionReference);
    if (existing.exists && existing.data().groupID !== groupID) {
      throw new HttpsError("already-exists", "This subscription already sponsors another group.");
    }
    firestoreTransaction.set(transactionReference, {
      groupID,
      sponsorID: request.auth.uid,
      productID: premiumProductID,
      environment: verified.environment,
      expiresAt: Timestamp.fromMillis(transaction.expiresDate),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    firestoreTransaction.update(groupReference, {
      premium: {
        productID: premiumProductID,
        originalTransactionID: transaction.originalTransactionId,
        sponsorID: request.auth.uid,
        expiresAt: Timestamp.fromMillis(transaction.expiresDate),
        status: "active",
        environment: verified.environment,
        updatedAt: Timestamp.now(),
      },
    });
  });
  return {active: true, expiresAt: transaction.expiresDate};
});

exports.appStoreServerNotifications = onRequest(async (request, response) => {
  const signedPayload = typeof request.body?.signedPayload === "string" ? request.body.signedPayload : "";
  if (!signedPayload) {
    response.status(400).send("Missing signed payload");
    return;
  }
  try {
    let notification;
    let verifier;
    try {
      notification = await productionVerifier.verifyAndDecodeNotification(signedPayload);
      verifier = productionVerifier;
    } catch (_) {
      notification = await sandboxVerifier.verifyAndDecodeNotification(signedPayload);
      verifier = sandboxVerifier;
    }
    const signedTransaction = notification.data?.signedTransactionInfo;
    if (!signedTransaction) {
      response.status(200).send("No transaction update");
      return;
    }
    const transaction = await verifier.verifyAndDecodeTransaction(signedTransaction);
    if (transaction.productId !== premiumProductID || !transaction.originalTransactionId) {
      response.status(200).send("Ignored product");
      return;
    }
    const database = getFirestore();
    const transactionReference = database.doc(`premiumTransactions/${transaction.originalTransactionId}`);
    const mapping = (await transactionReference.get()).data();
    if (!mapping?.groupID) {
      response.status(200).send("Purchase has not been assigned to a group");
      return;
    }
    const expiresAt = transaction.expiresDate ? Timestamp.fromMillis(transaction.expiresDate) : Timestamp.now();
    const active = !transaction.revocationDate && (transaction.expiresDate ?? 0) > Date.now();
    const batch = database.batch();
    batch.set(transactionReference, {expiresAt, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    batch.update(database.doc(`groups/${mapping.groupID}`), {
      "premium.expiresAt": expiresAt,
      "premium.status": active ? "active" : (transaction.revocationDate ? "revoked" : "expired"),
      "premium.updatedAt": FieldValue.serverTimestamp(),
    });
    await batch.commit();
    response.status(200).send("OK");
  } catch (error) {
    console.error("Invalid App Store server notification", error);
    response.status(400).send("Invalid signed payload");
  }
});

exports.setGroupTheme = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in to change a theme.");
  const groupID = typeof request.data?.groupID === "string" ? request.data.groupID.trim() : "";
  const themeID = typeof request.data?.themeID === "string" ? request.data.themeID : "";
  if (!["gold", "coral", "rose", "forest", "cobalt", "plum"].includes(themeID)) {
    throw new HttpsError("invalid-argument", "Choose a valid group theme.");
  }
  const database = getFirestore();
  const {snapshot, group} = await requirePremiumMember(database, groupID, request.auth.uid);
  if (group.ownerID !== request.auth.uid) throw new HttpsError("permission-denied", "Only the group owner can change its theme.");
  await snapshot.ref.update({themeID});
  return {themeID};
});

exports.createTimeCapsule = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in to create a capsule.");
  const groupID = typeof request.data?.groupID === "string" ? request.data.groupID.trim() : "";
  const kind = typeof request.data?.kind === "string" ? request.data.kind : "";
  const title = typeof request.data?.title === "string" ? request.data.title.trim() : "";
  const content = typeof request.data?.content === "string" ? request.data.content.trim() : "";
  const unlockMilliseconds = Number(request.data?.unlockAt);
  if (!["question", "answer", "prediction"].includes(kind) || !title || title.length > 100 || !content || content.length > 3000) {
    throw new HttpsError("invalid-argument", "Complete the capsule before sealing it.");
  }
  if (!Number.isFinite(unlockMilliseconds) || unlockMilliseconds <= Date.now()) {
    throw new HttpsError("invalid-argument", "Choose a future unlock date.");
  }
  const database = getFirestore();
  await requirePremiumMember(database, groupID, request.auth.uid);
  const user = (await database.doc(`users/${request.auth.uid}`).get()).data();
  const capsuleReference = database.doc(`groups/${groupID}`).collection("timeCapsules").doc();
  const batch = database.batch();
  batch.create(capsuleReference, {
    groupID,
    kind,
    title,
    creatorID: request.auth.uid,
    creatorName: user?.displayName ?? "Blurb friend",
    unlockAt: Timestamp.fromMillis(unlockMilliseconds),
    createdAt: FieldValue.serverTimestamp(),
  });
  batch.create(database.doc(`premiumTimeCapsuleContents/${groupID}_${capsuleReference.id}`), {
    groupID,
    capsuleID: capsuleReference.id,
    content,
    unlockAt: Timestamp.fromMillis(unlockMilliseconds),
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return {capsuleID: capsuleReference.id};
});

exports.openTimeCapsule = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in to open a capsule.");
  const groupID = typeof request.data?.groupID === "string" ? request.data.groupID.trim() : "";
  const capsuleID = typeof request.data?.capsuleID === "string" ? request.data.capsuleID.trim() : "";
  const database = getFirestore();
  await requirePremiumMember(database, groupID, request.auth.uid);
  const contentSnapshot = await database.doc(`premiumTimeCapsuleContents/${groupID}_${capsuleID}`).get();
  const content = contentSnapshot.data();
  if (!contentSnapshot.exists) throw new HttpsError("not-found", "This capsule is unavailable.");
  if (content.unlockAt?.toMillis?.() > Date.now()) throw new HttpsError("failed-precondition", "This capsule is still sealed.");
  return {content: content.content};
});

async function monthlyProgress(database, groupID, memberIDs, date = new Date()) {
  const newsletter = newsletterContext(date);
  const monthKey = photoMonthKey(date);
  const [postsSnapshot, customQuestionsSnapshot] = await Promise.all([
    database.collection("posts").where("groupID", "==", groupID).get(),
    database.collection("groups").doc(groupID).collection("newsletterQuestions")
        .where("monthKey", "==", monthKey).get(),
  ]);
  const promptIDs = [
    ...newsletter.promptIDs,
    ...customQuestionsSnapshot.docs
        .map((document) => document.data().promptID)
        .filter((promptID) => typeof promptID === "string" && promptID.startsWith("newsletter-custom-")),
  ];
  const questionCounts = memberQuestionCounts(
      postsSnapshot.docs.map((document) => document.data()),
      memberIDs,
      promptIDs,
  );
  const photoSelections = await Promise.all(memberIDs.map((userID) => database.doc(
      `users/${userID}/photoOfMonthSelections/${selectionDocumentID(groupID, monthKey)}`,
  ).get()));
  return new Map(memberIDs.map((userID, index) => [userID, {
    newsletterAnsweredCount: questionCounts.get(userID) ?? 0,
    newsletterQuestionCount: promptIDs.length,
    hasPhotoOfMonth: photoSelections[index].exists,
  }]));
}

exports.getGroupMembers = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to view group members.");
  const groupID = typeof request.data?.groupID === "string" ? request.data.groupID.trim() : "";
  if (!groupID) throw new HttpsError("invalid-argument", "A group is required.");

  const database = getFirestore();
  const groupSnapshot = await database.doc(`groups/${groupID}`).get();
  const group = groupSnapshot.data();
  if (!groupSnapshot.exists || !(group?.memberIDs ?? []).includes(request.auth.uid)) {
    throw new HttpsError("permission-denied", "You must be a member of this group.");
  }

  const memberIDs = [...new Set(group.memberIDs ?? [])].filter((id) => typeof id === "string" && id);
  const includeMonthlyProgress = request.data?.includeMonthlyProgress !== false;
  const [profiles, progress] = await Promise.all([
    Promise.all(memberIDs.map((id) => database.doc(`users/${id}`).get())),
    includeMonthlyProgress ? monthlyProgress(database, groupID, memberIDs) : Promise.resolve(new Map()),
  ]);
  return {
    members: profiles.map((profile, index) => ({
      id: memberIDs[index],
      displayName: profile.data()?.displayName || "Blurb friend",
      ...(profile.data()?.photoURL ? {photoURL: profile.data().photoURL} : {}),
      ...(progress.get(memberIDs[index]) ?? {}),
    })),
  };
});

exports.nudgeMonthlyProgress = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in to send a nudge.");
  const groupID = typeof request.data?.groupID === "string" ? request.data.groupID.trim() : "";
  const memberID = typeof request.data?.memberID === "string" ? request.data.memberID.trim() : "";
  if (!groupID || !memberID) throw new HttpsError("invalid-argument", "A group and member are required.");
  if (memberID === request.auth.uid) throw new HttpsError("invalid-argument", "You can’t nudge yourself.");

  const database = getFirestore();
  const groupSnapshot = await database.doc(`groups/${groupID}`).get();
  const group = groupSnapshot.data();
  if (!groupSnapshot.exists || group?.ownerID !== request.auth.uid) {
    throw new HttpsError("permission-denied", "Only the group owner can send nudges.");
  }
  if (!(group.memberIDs ?? []).includes(memberID)) {
    throw new HttpsError("not-found", "That person is no longer in this group.");
  }

  const progress = (await monthlyProgress(database, groupID, [memberID])).get(memberID);
  const needsQuestions = progress.newsletterAnsweredCount < progress.newsletterQuestionCount;
  const needsPhoto = !progress.hasPhotoOfMonth;
  if (!needsQuestions && !needsPhoto) {
    throw new HttpsError("failed-precondition", "This member has completed their monthly check-in.");
  }

  const [memberSnapshot, senderSnapshot] = await Promise.all([
    database.doc(`users/${memberID}`).get(),
    database.doc(`users/${request.auth.uid}`).get(),
  ]);
  const member = memberSnapshot.data();
  if (member?.notificationPreferences?.dailyReminders !== true) {
    throw new HttpsError("failed-precondition", "This member has reminder notifications turned off.");
  }
  const tokens = [...new Set(member?.fcmTokens ?? [])]
      .filter((token) => typeof token === "string" && token);
  if (!tokens.length) {
    throw new HttpsError("failed-precondition", "This member does not have notifications available right now.");
  }

  const today = localDateKey(new Date());
  const receipt = database.doc(`notificationDeliveries/monthly-nudge-${groupID}-${memberID}-${today}`);
  const claimed = await database.runTransaction(async (transaction) => {
    if ((await transaction.get(receipt)).exists) return false;
    transaction.create(receipt, {
      groupID,
      memberID,
      senderID: request.auth.uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!claimed) throw new HttpsError("resource-exhausted", "You already nudged this member today.");

  const copy = nudgeMessage({
    senderName: senderSnapshot.data()?.displayName,
    groupName: group.name,
    needsQuestions,
    needsPhoto,
  });
  let sentCount = 0;
  const userReference = database.doc(`users/${memberID}`);
  for (let offset = 0; offset < tokens.length; offset += 500) {
    const batch = tokens.slice(offset, offset + 500);
    const response = await getMessaging().sendEachForMulticast({
      tokens: batch,
      notification: copy,
      data: {type: "monthlyProgressNudge", groupID},
      apns: {payload: {aps: {sound: "default"}}},
    });
    sentCount += response.successCount;
    const invalid = batch.filter((_, index) => [
      "messaging/invalid-registration-token",
      "messaging/registration-token-not-registered",
    ].includes(response.responses[index].error?.code));
    if (invalid.length) await userReference.update({fcmTokens: FieldValue.arrayRemove(...invalid)});
  }
  if (!sentCount) {
    await receipt.delete();
    throw new HttpsError("unavailable", "The notification couldn’t be delivered right now.");
  }
  return {sent: true};
});

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

  const monthKey = photoMonthKey(new Date());
  let post;
  if (input.postID) {
    const postSnapshot = await database.doc(`posts/${input.postID}`).get();
    post = postSnapshot.data();
    if (!postSnapshot.exists || post.groupID !== input.groupID || post.authorID !== userID) {
      throw new HttpsError("permission-denied", "Choose one of your own Blurbs from this group.");
    }
    if (typeof post.imageURL !== "string" || !post.imageURL) {
      throw new HttpsError("failed-precondition", "The selected Blurb does not have a photo.");
    }
    const createdAt = post.createdAt?.toDate?.();
    if (!createdAt || photoMonthKey(createdAt) !== monthKey) {
      throw new HttpsError("failed-precondition", "Choose a photo posted during the current month.");
    }
  } else {
    if (!validPrivatePhotoPath(input.storagePath, input.groupID, userID, monthKey)) {
      throw new HttpsError("invalid-argument", "Invalid private photo path.");
    }
    const file = getStorage().bucket().file(input.storagePath);
    const [exists] = await file.exists();
    if (!exists) throw new HttpsError("not-found", "The uploaded photo was not found.");
    const [metadata] = await file.getMetadata();
    if (!metadata.contentType?.startsWith("image/") || Number(metadata.size) >= 5 * 1024 * 1024) {
      throw new HttpsError("failed-precondition", "Upload a photo smaller than 5 MB.");
    }
    const profile = (await database.doc(`users/${userID}`).get()).data();
    post = {
      imageURL: await getDownloadURL(file),
      authorName: profile?.displayName ?? "Blurb friend",
      createdAt: Timestamp.now(),
    };
  }

  const reference = database.doc(
      `users/${userID}/photoOfMonthSelections/${selectionDocumentID(input.groupID, monthKey)}`,
  );
  await database.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    const selection = {
      ...buildSelection({
        groupID: input.groupID, postID: input.postID, post, userID, monthKey, caption: input.caption,
      }),
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (!existing.exists) selection.createdAt = FieldValue.serverTimestamp();
    transaction.set(reference, selection, {merge: true});
  });

  return {monthKey, postID: input.postID};
});

exports.updatePhotoOfMonthCaption = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in to update your caption.");
  const groupID = typeof request.data?.groupID === "string" ? request.data.groupID.trim() : "";
  if (!groupID) throw new HttpsError("invalid-argument", "A group is required.");
  let caption;
  try {
    caption = validateCaption(request.data?.caption);
  } catch (error) {
    throw new HttpsError("invalid-argument", error.message);
  }

  const database = getFirestore();
  const userID = request.auth.uid;
  const group = (await database.doc(`groups/${groupID}`).get()).data();
  if (!(group?.memberIDs ?? []).includes(userID)) {
    throw new HttpsError("permission-denied", "You are not a member of this group.");
  }
  const monthKey = photoMonthKey(new Date());
  const reference = database.doc(
      `users/${userID}/photoOfMonthSelections/${selectionDocumentID(groupID, monthKey)}`,
  );
  if (!(await reference.get()).exists) {
    throw new HttpsError("failed-precondition", "Choose a Photo of the Month first.");
  }
  await reference.update({caption, updatedAt: FieldValue.serverTimestamp()});
  return {monthKey};
});

exports.setSongOfMonthSelection = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in to choose a song.");
  let input;
  try {
    input = validateSongSelectionInput(request.data);
  } catch (error) {
    throw new HttpsError("invalid-argument", error.message);
  }

  const database = getFirestore();
  const userID = request.auth.uid;
  const group = (await database.doc(`groups/${input.groupID}`).get()).data();
  if (!(group?.memberIDs ?? []).includes(userID)) {
    throw new HttpsError("permission-denied", "You are not a member of this group.");
  }
  const monthKey = photoMonthKey(new Date());
  const reference = database.doc(
      `users/${userID}/songOfMonthSelections/${selectionDocumentID(input.groupID, monthKey)}`,
  );
  if (input.remove) {
    await reference.delete();
    return {monthKey, removed: true};
  }

  const profile = (await database.doc(`users/${userID}`).get()).data();
  await database.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    const selection = {
      groupID: input.groupID,
      monthKey,
      userID,
      title: input.title,
      artist: input.artist,
      authorName: profile?.displayName ?? "Blurb friend",
      updatedAt: FieldValue.serverTimestamp(),
    };
    if (!existing.exists) selection.createdAt = FieldValue.serverTimestamp();
    transaction.set(reference, selection, {merge: true});
  });
  return {monthKey};
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
    if (member?.notificationPreferences?.replyNotifications !== true) continue;
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

exports.notifyUnansweredGroupMembers = onDocumentCreated("posts/{postID}", async (event) => {
  const post = event.data?.data();
  if (!post || post.isSample || !post.groupID || !post.authorID || post.promptID?.startsWith("newsletter-")) return;

  const database = getFirestore();
  const groupSnapshot = await database.doc(`groups/${post.groupID}`).get();
  const group = groupSnapshot.data();
  const memberIDs = group?.memberIDs ?? [];
  if (!groupSnapshot.exists || !memberIDs.includes(post.authorID)) return;

  const today = localDateKey(new Date());
  const postsSnapshot = await database.collection("posts").where("groupID", "==", post.groupID).get();
  const answeredAuthorIDs = postsSnapshot.docs
      .filter((document) => {
        const createdAt = document.data().createdAt?.toDate?.();
        return createdAt && localDateKey(createdAt) === today;
      })
      .map((document) => document.data().authorID)
      .filter(Boolean);
  const recipientIDs = unansweredMemberIDs({memberIDs, senderID: post.authorID, answeredAuthorIDs});
  const sender = (await database.doc(`users/${post.authorID}`).get()).data();

  for (const userID of recipientIDs) {
    const userReference = database.doc(`users/${userID}`);
    const user = (await userReference.get()).data();
    if (user?.notificationPreferences?.dailyReminders !== true) continue;
    const tokens = [...new Set(user?.fcmTokens ?? [])].filter((token) => typeof token === "string" && token);
    if (!tokens.length) continue;

    const counter = database.doc(`notificationDailyCounts/${today}_${userID}`);
    const receipt = database.doc(`notificationDeliveries/social-${event.id}-${userID}`);
    const claimed = await database.runTransaction(async (transaction) => {
      const [counterSnapshot, receiptSnapshot] = await Promise.all([
        transaction.get(counter), transaction.get(receipt),
      ]);
      if (receiptSnapshot.exists || (counterSnapshot.data()?.socialNudgeCount ?? 0) >= 2) return false;
      transaction.set(counter, {
        userID,
        dateKey: today,
        socialNudgeCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.create(receipt, {createdAt: FieldValue.serverTimestamp()});
      return true;
    });
    if (!claimed) continue;

    for (let offset = 0; offset < tokens.length; offset += 500) {
      const batch = tokens.slice(offset, offset + 500);
      const response = await getMessaging().sendEachForMulticast({
        tokens: batch,
        notification: {
          title: `${sender?.displayName ?? post.authorName ?? "A friend"} posted in ${group.name ?? "your group"}`,
          body: "You haven’t posted yet—share your Blurb and join the conversation.",
        },
        data: {postID: event.params.postID, groupID: post.groupID, type: "answerNudge"},
        apns: {payload: {aps: {sound: "default"}}},
      });
      const invalid = batch.filter((_, index) => ["messaging/invalid-registration-token", "messaging/registration-token-not-registered"].includes(response.responses[index].error?.code));
      if (invalid.length) await userReference.update({fcmTokens: FieldValue.arrayRemove(...invalid)});
    }
  }
});

exports.remindNewsletterQuestion = onSchedule(
    {schedule: "0 8 * * 5", timeZone: "America/Los_Angeles"},
    async () => {
      const database = getFirestore();
      const now = new Date();
      const parts = new Intl.DateTimeFormat("en-US", {
        year: "numeric", month: "2-digit", day: "2-digit", timeZone: "America/Los_Angeles",
      }).formatToParts(now);
      const year = Number(parts.find((part) => part.type === "year").value);
      const month = Number(parts.find((part) => part.type === "month").value);
      const day = Number(parts.find((part) => part.type === "day").value);
      const ordinal = Math.floor((day - 1) / 7) + 1;
      if (ordinal > 4) return;

      const groups = await database.collection("groups").get();
      const memberIDs = [...new Set(groups.docs.flatMap((document) => document.data().memberIDs ?? []))]
          .filter((id) => typeof id === "string" && id);
      const monthKey = `${year}-${String(month).padStart(2, "0")}`;

      for (const userID of memberIDs) {
        const receipt = database.doc(`notificationDeliveries/newsletter-${monthKey}-${ordinal}-${userID}`);
        const claimed = await database.runTransaction(async (transaction) => {
          if ((await transaction.get(receipt)).exists) return false;
          transaction.create(receipt, {createdAt: FieldValue.serverTimestamp()});
          return true;
        });
        if (!claimed) continue;

        const userReference = database.doc(`users/${userID}`);
        const user = (await userReference.get()).data();
        if (user?.notificationPreferences?.dailyReminders !== true) continue;
        const tokens = [...new Set(user.fcmTokens ?? [])].filter((token) => typeof token === "string" && token);
        if (!tokens.length) continue;
        const response = await getMessaging().sendEachForMulticast({
          tokens,
          notification: {
            title: "Your monthly question is ready",
            body: ordinal === 1
              ? "Answer the first newsletter question of the month. Your Daily Blurb is still waiting too."
              : `Newsletter question ${ordinal} of 4 is ready. Catch up anytime before the month ends.`,
          },
          data: {type: "newsletterQuestion", monthKey, ordinal: String(ordinal)},
          apns: {payload: {aps: {sound: "default"}}},
        });
        const invalid = tokens.filter((_, index) => ["messaging/invalid-registration-token", "messaging/registration-token-not-registered"]
            .includes(response.responses[index].error?.code));
        if (invalid.length) await userReference.update({fcmTokens: FieldValue.arrayRemove(...invalid)});
      }
    },
);

function previousNewsletterMonth(date = new Date()) {
  const [year, month] = photoMonthKey(date).split("-").map(Number);
  const target = new Date(Date.UTC(year, month - 2, 15));
  return {
    monthKey: `${target.getUTCFullYear()}-${String(target.getUTCMonth() + 1).padStart(2, "0")}`,
    monthLabel: target.toLocaleDateString("en-US", {month: "long", year: "numeric", timeZone: "UTC"}),
  };
}

async function generateNewsletterEdition(database, groupDocument, monthKey, monthLabel) {
  const editionReference = database.collection("newsletterEditions")
      .doc(`${groupDocument.id}_${monthKey}`);
  const existingEdition = await editionReference.get();
  if (existingEdition.exists && (existingEdition.data()?.scoringVersion ?? 1) >= 2) return false;

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

  const totals = {};
  const counts = {};
  const entries = [];
  let photoCount = 0;
  let mostLiked = null;
  let mostCommented = null;
  const cityLocations = [];
  for (const document of monthPosts) {
    const post = document.data();
    const isNewsletterQuestion = post.promptID?.startsWith("newsletter-") === true;
    const cityLocation = normalizeCityLocation(post.cityLocation);
    if (!isNewsletterQuestion) {
      if (cityLocation) cityLocations.push(cityLocation);
      const responseLikes = Array.isArray(post.likeIDs) ? post.likeIDs.length : 0;
      totals[post.authorName] = (totals[post.authorName] ?? 0) + (post.pointsAwarded ?? 0) + responseLikes;
      counts[post.authorName] = (counts[post.authorName] ?? 0) + 1;
      if (post.imageURL) photoCount += 1;
      const summary = {postID: document.id, authorName: post.authorName, prompt: post.prompt ?? "", answer: post.answer ?? "", value: 0};
      const likes = responseLikes;
      const comments = post.commentCount ?? 0;
      if (!mostLiked || likes > mostLiked.value) mostLiked = {...summary, value: likes};
      if (!mostCommented || comments > mostCommented.value) mostCommented = {...summary, value: comments};

      const commentsSnapshot = await document.ref.collection("comments").get();
      for (const commentDocument of commentsSnapshot.docs) {
        const comment = commentDocument.data();
        const replyLikes = Array.isArray(comment.likeIDs) ? comment.likeIDs.length : 0;
        if (replyLikes > 0 && typeof comment.authorName === "string" && comment.authorName) {
          totals[comment.authorName] = (totals[comment.authorName] ?? 0) + replyLikes;
        }
      }
    } else {
      entries.push({
        postID: document.id,
        authorID: post.authorID,
        authorName: post.authorName,
        authorPhotoURL: post.authorPhotoURL ?? null,
        answer: post.answer ?? "",
        prompt: post.prompt ?? "",
        promptID: post.promptID ?? "",
        imageURL: post.imageURL ?? null,
        cityLocation: cityLocation ? {
          city: cityLocation.city,
          region: cityLocation.region,
          countryCode: cityLocation.countryCode,
        } : null,
        pollOptions: post.pollOptions ?? [],
        createdAt: post.createdAt,
        pointsAwarded: 0,
      });
    }
  }

  for (const userID of group.memberIDs ?? []) {
    const selectionID = selectionDocumentID(groupDocument.id, monthKey);
    const photoSnapshot = await database.doc(
        `users/${userID}/photoOfMonthSelections/${selectionID}`,
    ).get();
    const selection = photoSnapshot.data();
    if (selection?.imageURL) {
      entries.push({
        postID: `photo-of-month-${userID}-${monthKey}`,
        sourcePostID: selection.postID,
        authorID: userID,
        authorName: selection.authorName ?? "Blurb friend",
        answer: selection.caption ?? "",
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
  await editionReference.set({
    groupID: groupDocument.id,
    groupName: group.name,
    viewerIDs: group.memberIDs ?? [],
    monthKey,
    monthLabel,
    scoringVersion: 2,
    generatedAt: FieldValue.serverTimestamp(),
    entries,
    winners: {
      mostAnswers: mostAnswers ? {name: mostAnswers[0], value: mostAnswers[1]} : null,
      mostPoints: mostPoints ? {name: mostPoints[0], value: mostPoints[1]} : null,
    },
    stats: {
      answerCount: monthPosts.filter((document) => !document.data().promptID?.startsWith("newsletter-")).length,
      questionCount: new Set(entries.filter((entry) => entry.promptID?.startsWith("newsletter-")).map((entry) => entry.promptID)).size,
      photoCount,
      participatingMemberCount: Object.keys(counts).length,
      groupMemberCount: (group.memberIDs ?? []).length,
      mostLiked,
      mostCommented,
      cities: aggregateCities(cityLocations),
    },
  });
  return true;
}

exports.ensurePreviousNewsletter = onCall(async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Sign in to open this newsletter.");
  const groupID = typeof request.data?.groupID === "string" ? request.data.groupID.trim() : "";
  if (!groupID) throw new HttpsError("invalid-argument", "A group is required.");

  const database = getFirestore();
  const groupDocument = await database.doc(`groups/${groupID}`).get();
  if (!groupDocument.exists || !(groupDocument.data()?.memberIDs ?? []).includes(request.auth.uid)) {
    throw new HttpsError("permission-denied", "You must be a member of this group.");
  }
  const {monthKey, monthLabel} = previousNewsletterMonth();
  const generated = await generateNewsletterEdition(database, groupDocument, monthKey, monthLabel);
  return {generated, monthKey};
});

exports.generateMonthlyNewsletters = onSchedule(
    {schedule: "0 8 1 * *", timeZone: "America/Los_Angeles"},
    async () => {
      const database = getFirestore();
      const {monthKey, monthLabel} = previousNewsletterMonth();
      const groups = await database.collection("groups").get();
      for (const groupDocument of groups.docs) {
        await generateNewsletterEdition(database, groupDocument, monthKey, monthLabel);
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
