function validateSongSelectionInput(data) {
  const groupID = typeof data?.groupID === "string" ? data.groupID.trim() : "";
  const remove = data?.remove === true;
  const title = typeof data?.title === "string" ? data.title.trim() : "";
  const artist = typeof data?.artist === "string" ? data.artist.trim() : "";
  if (!groupID) throw new Error("A group is required.");
  if (remove) return {groupID, title: "", artist: "", remove: true};
  if (!title) throw new Error("Add a song title.");
  if (title.length > 100 || artist.length > 100) {
    throw new Error("Keep the song title and artist under 100 characters each.");
  }
  return {groupID, title, artist, remove: false};
}

function songDisplayText(title, artist) {
  return artist ? `${title} — ${artist}` : title;
}

module.exports = {songDisplayText, validateSongSelectionInput};
