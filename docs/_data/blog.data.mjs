import { createContentLoader } from "vitepress";

export default createContentLoader("blog/posts/*.md", {
  transform(raw) {
    return raw
      .filter(({ frontmatter }) => frontmatter.published !== false)
      .map(({ url, frontmatter }) => ({
        title: frontmatter.title ?? "Untitled",
        description: frontmatter.description,
        author: authorName(frontmatter.author),
        url,
        date: formatDate(frontmatter.date),
      }))
      .sort((left, right) => right.date.time - left.date.time);
  },
});

function formatDate(raw) {
  const date = new Date(raw);
  date.setUTCHours(12);

  return {
    time: Number(date),
    string: date.toLocaleDateString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
    }),
  };
}

function authorName(author) {
  if (!author) return undefined;
  if (typeof author === "string") return author;

  return author.name;
}
