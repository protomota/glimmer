import { readFile, writeFile } from "node:fs/promises";
import * as source from "../../src/data.ts";

const seed = await readFile(new URL("../../supabase/seed_lessons.sql", import.meta.url), "utf8");
const fields = "'((?:[^']|'')*)'";
const pattern = new RegExp(
  `\\(${fields}, (\\d+), ${fields}, ${fields}, ${fields}, (\\d+), ${fields}, ${fields}, ${fields}, \\$pg\\$(.*?)\\$pg\\$::jsonb, \\d+\\)`, "gs",
);
const unquote = (value) => value.replaceAll("''", "'");
const lessons = [...seed.matchAll(pattern)].map(([, slug, number, arc, title, tagline, minutes, , hero, heroAlt, pages]) => ({
  slug, number: Number(number), arc: unquote(arc), title: unquote(title), tagline: unquote(tagline),
  minutes: Number(minutes), hero, heroAlt: unquote(heroAlt), pages: JSON.parse(pages),
}));
if (lessons.length !== 90 || lessons.some((item, index) => item.number !== index + 1)) {
  throw new Error("The original lesson catalog did not parse in full.");
}
// Keep native editorial changes reproducible without changing the original Expo curriculum.
const editorial = JSON.parse(await readFile(new URL("../LibraryContent/Editorial.json", import.meta.url), "utf8"));
for (const ids of [editorial.practiceTopics.map(topic => topic.id), editorial.practiceTopics.flatMap(topic => topic.exercises.map(practice => practice.id))]) {
  if (ids.some(id => typeof id !== "string" || !/^[a-z][a-z0-9_-]*$/.test(id)) || new Set(ids).size !== ids.length) {
    throw new Error("Coaching topics and practices each require unique, permanent identifiers.");
  }
}
for (const [number, update] of Object.entries(editorial.takeaways)) {
  const lesson = lessons.find(item => item.number === Number(number));
  const page = lesson?.pages.find(item => item.kind === "takeaway");
  if (!page || !update.body || !update.tryToday) throw new Error(`Invalid editorial takeaway for lesson ${number}`);
  page.body = `${update.body}\n\n**Try today:** ${update.tryToday}`;
  page.tryToday = update.tryToday;
}
// Deeper rewrites of existing lessons. IDs, numbers, page kinds and option counts stay
// fixed because journals store answers by page position.
for (const [number, edit] of Object.entries(editorial.lessonEdits ?? {})) {
  const lesson = lessons.find(item => item.number === Number(number));
  if (!lesson) throw new Error(`Lesson edit for missing lesson ${number}`);
  if (edit.pages) {
    if (edit.pages.length !== lesson.pages.length) throw new Error(`Lesson ${number} must keep ${lesson.pages.length} pages`);
    edit.pages.forEach((page, index) => {
      const original = lesson.pages[index];
      if (page.kind !== original.kind || (original.options?.length ?? 0) !== (page.options?.length ?? 0)) {
        throw new Error(`Lesson ${number} page ${index + 1} must keep its kind and option count`);
      }
      if (page.kind === "takeaway" && !page.tryToday) throw new Error(`Lesson ${number} takeaway needs tryToday`);
    });
  }
  Object.assign(lesson, Object.fromEntries(["arc", "title", "tagline", "minutes", "pages"].filter(key => edit[key] !== undefined).map(key => [key, edit[key]])));
  for (const page of lesson.pages) {
    if (page.kind === "takeaway" && page.tryToday && !page.body.includes("**Try today:**")) page.body = `${page.body}\n\n**Try today:** ${page.tryToday}`;
  }
}
// The Deep Path: lessons appended after the original 90.
for (const extra of editorial.extraLessons ?? []) {
  if (extra.number !== lessons.length + 1 || lessons.some(item => item.slug === extra.slug)) throw new Error(`Extra lesson ${extra.slug} must be numbered ${lessons.length + 1} with a new slug`);
  if (!extra.title || !extra.arc || !extra.tagline || !(extra.minutes > 0) || !Array.isArray(extra.pages) || extra.pages.at(-1)?.kind !== "takeaway") {
    throw new Error(`Extra lesson ${extra.number} is incomplete`);
  }
  const pages = extra.pages.map(page => page.kind === "takeaway" && page.tryToday && !page.body.includes("**Try today:**")
    ? { ...page, body: `${page.body}\n\n**Try today:** ${page.tryToday}` } : page);
  lessons.push({ slug: extra.slug, number: extra.number, arc: extra.arc, title: extra.title, tagline: extra.tagline,
    minutes: extra.minutes, hero: null, heroAlt: null, pages });
}
const levels = new Set([1, 2, 3, 4, 5]);
for (const practice of editorial.practiceTopics.flatMap(topic => topic.exercises)) {
  if (practice.level !== undefined && !levels.has(practice.level)) throw new Error(`Practice ${practice.id} has an invalid level`);
}
const challengeLevels = editorial.challengeLevels ?? {};
const challenges = [...source.CHALLENGES.map(item => challengeLevels[item.id] ? { ...item, level: challengeLevels[item.id] } : item),
  ...(editorial.challenges ?? [])];
if (new Set(challenges.map(item => item.id)).size !== challenges.length
  || challenges.some(item => item.level !== undefined && !levels.has(item.level))
  || challenges.some(item => !item.title || !item.sub || !(item.mins > 0) || !(item.coins > 0) || item.teach?.length < 1 || !item.q || item.opts?.length < 2 || !item.action || !item.done)) {
  throw new Error("Challenges need unique IDs, a valid level and every page");
}
// Apps added for the native app, placed after a named original source.
const sources = source.SOURCES.map(({ name }) => name);
const tags = Object.fromEntries(source.SOURCES.map(({ name }) => [name, source.contentTypesFor(name)]));
for (const added of editorial.sources ?? []) {
  if (!added.name || !Array.isArray(added.tags) || sources.includes(added.name)) throw new Error(`Invalid editorial source ${added.name}`);
  const position = sources.indexOf(added.after);
  sources.splice(position < 0 ? sources.length : position + 1, 0, added.name);
  tags[added.name] = added.tags;
}
const catalog = {
  sources,
  activities: [...source.ACT_POOL, ...(editorial.activities ?? [])],
  people: source.PPL_POOL,
  tags,
  defaultTags: source.contentTypesFor(""),
  initialTasks: source.INITIAL_TASKS,
  library: source.TASK_LIBRARY,
  preload: source.PRELOAD_SUGGESTIONS,
  onboarding: source.ONB_STEPS.map(step => step.key === "primary_goal" ? {
    ...step, mode: "multi", kicker: "Your goals", title: "What would you like help with?", sub: "Choose all that apply.",
  } : step),
  challenges,
  energy: source.ENERGY_DEFS,
  energyMessages: source.ENERGY_MSGS,
  habits: source.HABIT_DATA,
  cleaning: source.CLEAN_DATA,
  seasonal: editorial.seasonal,
  quotes: editorial.quotes,
  coach: editorial.coach,
  startingPractices: editorial.startingPractices,
  practiceTopics: editorial.practiceTopics,
  praise: source.PRAISE,
  lessons,
};
await writeFile(new URL("../LibraryContent/Catalog.json", import.meta.url), JSON.stringify(catalog, null, 2) + "\n");
