function normalizeCityLocation(value) {
  if (!value || typeof value !== "object") return null;
  const city = typeof value.city === "string" ? value.city.trim() : "";
  if (!city) return null;
  const region = typeof value.region === "string" && value.region.trim() ? value.region.trim() : null;
  const countryCode = typeof value.countryCode === "string" && value.countryCode.trim() ? value.countryCode.trim().toUpperCase() : null;
  return {
    city,
    region,
    countryCode,
    key: [city, region ?? "", countryCode ?? ""].map((part) => part.toLocaleLowerCase("en-US")).join("|"),
  };
}

function aggregateCities(values) {
  const counts = new Map();
  for (const value of values) {
    const location = normalizeCityLocation(value);
    if (!location) continue;
    const current = counts.get(location.key);
    counts.set(location.key, current ? {...current, count: current.count + 1} : {
      city: location.city,
      region: location.region,
      countryCode: location.countryCode,
      count: 1,
    });
  }
  return [...counts.values()].sort((left, right) => right.count - left.count || left.city.localeCompare(right.city));
}

module.exports = {aggregateCities, normalizeCityLocation};
