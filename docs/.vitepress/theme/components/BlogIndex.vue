<script setup>
import { data as posts } from "../../../_data/blog.data.mjs";

function getDateTime(time) {
  return new Date(time).toISOString();
}
</script>

<template>
  <ul class="blog-list">
    <li v-for="post of posts" :key="post.url" class="blog-entry">
      <article>
        <div class="metadata">
          <time :datetime="getDateTime(post.date.time)">
            {{ post.date.string }}
          </time>
          <span v-if="post.author">{{ post.author }}</span>
        </div>
        <h2 class="title">
          <a :href="post.url">{{ post.title }}</a>
        </h2>
        <p v-if="post.description" class="description">
          {{ post.description }}
        </p>
      </article>
    </li>
  </ul>
</template>

<style scoped>
.blog-list {
  list-style-type: none;
  padding: 0;
}

.blog-entry {
  border-bottom: 1px solid var(--vp-c-divider);
  margin-top: 3em;
}

.metadata {
  color: var(--vp-c-text-2);
  display: flex;
  flex-wrap: wrap;
  font-size: 14px;
  gap: 0.75em;
}

.metadata span::before {
  content: "by ";
}

.title {
  border: none;
  font-size: 22px;
  margin-top: 0;
  padding-top: 0;
}

.title a {
  font-weight: 600;
  text-decoration: none;
}

.description {
  color: var(--vp-c-text-2);
  line-height: 1.7;
  margin-top: 0;
}
</style>
