import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { basename } from "node:path";

const docsRoot = new URL("..", import.meta.url);
const postsDirectory = new URL("./blog/posts/", docsRoot);
const outputDirectory = new URL("./public/blog/", docsRoot);
const siteUrl = "https://docs.hive.tuist.dev";

const files = (await readdir(postsDirectory)).filter((file) => file.endsWith(".md"));
const posts = [];

for (const file of files) {
  const source = await readFile(new URL(file, postsDirectory), "utf8");
  const frontmatter = parseFrontmatter(source);

  if (frontmatter.published === "false") continue;
  if (!frontmatter.title || !frontmatter.date) continue;

  const date = new Date(frontmatter.date);
  if (Number.isNaN(date.valueOf())) continue;

  posts.push({
    title: frontmatter.title,
    description: frontmatter.description ?? "",
    author: frontmatter.author ?? "",
    date,
    url: `${siteUrl}/blog/posts/${basename(file, ".md")}`,
  });
}

posts.sort((left, right) => right.date - left.date);
const latestDate = posts[0]?.date ?? new Date();

await mkdir(outputDirectory, { recursive: true });
await writeFile(new URL("rss.xml", outputDirectory), buildRss(posts, latestDate));
await writeFile(new URL("atom.xml", outputDirectory), buildAtom(posts, latestDate));

function parseFrontmatter(source) {
  const match = source.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return {};

  return Object.fromEntries(
    match[1]
      .split("\n")
      .map((line) => line.match(/^([\w-]+):\s*(.*)$/))
      .filter(Boolean)
      .map(([, key, value]) => [key, value.replace(/^['"]|['"]$/g, "")]),
  );
}

function buildRss(posts, updated) {
  const items = posts
    .map(
      (post) => `
    <item>
      <title>${escapeXml(post.title)}</title>
      <link>${post.url}</link>
      <guid isPermaLink="true">${post.url}</guid>
      <pubDate>${post.date.toUTCString()}</pubDate>
      <description>${escapeXml(post.description)}</description>
      <dc:creator>${escapeXml(post.author)}</dc:creator>
    </item>`,
    )
    .join("");

  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Hive Blog</title>
    <link>${siteUrl}/blog/</link>
    <description>Product notes, release context, and implementation stories from the Hive project.</description>
    <language>en</language>
    <lastBuildDate>${updated.toUTCString()}</lastBuildDate>
    <atom:link href="${siteUrl}/blog/rss.xml" rel="self" type="application/rss+xml" />${items}
  </channel>
</rss>
`;
}

function buildAtom(posts, updated) {
  const entries = posts
    .map(
      (post) => `
  <entry>
    <title>${escapeXml(post.title)}</title>
    <id>${post.url}</id>
    <link href="${post.url}" />
    <updated>${post.date.toISOString()}</updated>
    <published>${post.date.toISOString()}</published>
    <author><name>${escapeXml(post.author || "Hive")}</name></author>
    <summary>${escapeXml(post.description)}</summary>
  </entry>`,
    )
    .join("");

  return `<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Hive Blog</title>
  <id>${siteUrl}/blog/</id>
  <link href="${siteUrl}/blog/" />
  <link rel="self" href="${siteUrl}/blog/atom.xml" />
  <updated>${updated.toISOString()}</updated>${entries}
</feed>
`;
}

function escapeXml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}
