import { listPosts, createPost, deletePost } from "../../lib/dynamo.js";
import { verifyAuth } from "../../lib/auth.js";

export const prerender = false;

export async function GET() {
  const posts = await listPosts();
  return new Response(JSON.stringify(posts), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

export async function POST({ request }) {
  const auth = await verifyAuth(request);
  if (!auth.ok) {
    return new Response(JSON.stringify({ error: auth.error }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const data = await request.json();
    const { title, description, body, tags } = data;

    if (!title || !body) {
      return new Response(
        JSON.stringify({ error: "Title and body are required." }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const slug = (data.slug || title)
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "");

    const post = await createPost({
      slug,
      title,
      description: description || "",
      body,
      author: auth.payload?.["cognito:username"] || "Admin",
      tags: Array.isArray(tags) ? tags : ["notes"],
      readingTime: `${Math.max(1, Math.ceil(body.split(/\s+/).length / 200))} min read`,
    });

    return new Response(JSON.stringify(post), {
      status: 201,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
}

export async function DELETE({ request }) {
  const auth = await verifyAuth(request);
  if (!auth.ok) {
    return new Response(JSON.stringify({ error: auth.error }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const { slug } = await request.json();
    if (!slug) {
      return new Response(
        JSON.stringify({ error: "slug is required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }
    const result = await deletePost(slug);
    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
}
