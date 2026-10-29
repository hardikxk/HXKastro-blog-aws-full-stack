import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
  UpdateCommand,
  DeleteCommand,
} from "@aws-sdk/lib-dynamodb";

const TABLE = process.env.DYNAMODB_TABLE || "astro-blog-table";
const REGION = process.env.AWS_REGION || "us-east-1";

let ddbDocClient = null;

function getClient() {
  if (!ddbDocClient) {
    const rawClient = new DynamoDBClient({ region: REGION });
    ddbDocClient = DynamoDBDocumentClient.from(rawClient, {
      marshallOptions: { removeUndefinedValues: true },
    });
  }
  return ddbDocClient;
}

/**
 * List all published posts from DynamoDB.
 * Returns [] if table is empty or unreachable.
 */
export async function listPosts() {
  try {
    const client = getClient();
    const result = await client.send(
      new QueryCommand({
        TableName: TABLE,
        KeyConditionExpression: "PK = :pk",
        ExpressionAttributeValues: {
          ":pk": "POSTS_INDEX",
        },
      })
    );
    return (result.Items || []).sort(
      (a, b) => new Date(b.published).valueOf() - new Date(a.published).valueOf()
    );
  } catch (err) {
    console.warn("Could not list posts from DynamoDB:", err.message);
    return [];
  }
}

/**
 * Get a single post by slug from DynamoDB.
 */
export async function getPost(slug) {
  try {
    const client = getClient();
    const result = await client.send(
      new GetCommand({
        TableName: TABLE,
        Key: {
          PK: `POST#${slug}`,
          SK: "METADATA",
        },
      })
    );
    return result.Item || null;
  } catch (err) {
    console.warn(`Could not get post ${slug} from DynamoDB:`, err.message);
    return null;
  }
}

/**
 * Save/publish a post into DynamoDB.
 */
export async function createPost({ slug, title, description, body, author = "Admin", tags = [], readingTime = "5 min read" }) {
  const client = getClient();
  const published = new Date().toISOString();
  const postItem = {
    PK: `POST#${slug}`,
    SK: "METADATA",
    slug,
    title,
    description: description || "",
    body: body || "",
    author,
    tags,
    readingTime,
    published,
    views: 0,
  };

  // 1. Put the full post record
  await client.send(
    new PutCommand({
      TableName: TABLE,
      Item: postItem,
    })
  );

  // 2. Put into index partition for fast querying of post summaries
  const indexItem = {
    PK: "POSTS_INDEX",
    SK: `POST#${slug}`,
    slug,
    title,
    description: description || "",
    published,
    author,
    tags,
    readingTime,
  };

  await client.send(
    new PutCommand({
      TableName: TABLE,
      Item: indexItem,
    })
  );

  return postItem;
}

/**
 * Increment view count atomically in DynamoDB.
 */
export async function incrementViews(slug) {
  try {
    const client = getClient();
    const res = await client.send(
      new UpdateCommand({
        TableName: TABLE,
        Key: {
          PK: `POST#${slug}`,
          SK: "METADATA",
        },
        UpdateExpression: "SET views = if_not_exists(views, :zero) + :inc",
        ExpressionAttributeValues: {
          ":inc": 1,
          ":zero": 0,
        },
        ReturnValues: "UPDATED_NEW",
      })
    );
    return res.Attributes?.views ?? 1;
  } catch (err) {
    console.warn(`Could not bump views for ${slug}:`, err.message);
    return 0;
  }
}

/**
 * Delete a post from DynamoDB (both detail and index records).
 */
export async function deletePost(slug) {
  const client = getClient();

  // Delete the full post record
  await client.send(
    new DeleteCommand({
      TableName: TABLE,
      Key: { PK: `POST#${slug}`, SK: "METADATA" },
    })
  );

  // Delete from the listings index
  await client.send(
    new DeleteCommand({
      TableName: TABLE,
      Key: { PK: "POSTS_INDEX", SK: `POST#${slug}` },
    })
  );

  return { deleted: slug };
}
