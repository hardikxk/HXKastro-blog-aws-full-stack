import express from "express";
import { randomUUID } from "crypto";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand, QueryCommand } from "@aws-sdk/lib-dynamodb";
import { SNSClient, PublishCommand } from "@aws-sdk/client-sns";

const PORT = process.env.PORT || 3000;
const TABLE = process.env.DYNAMODB_TABLE;
const TOPIC_ARN = process.env.SNS_TOPIC_ARN;

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: process.env.AWS_REGION }));
const sns = new SNSClient({ region: process.env.AWS_REGION });

const app = express();
app.use(express.json());

// Used by the ALB target group health check.
app.get("/health", (_req, res) => res.status(200).send("ok"));

// GET /api/comments?postId=xyz
app.get("/api/comments", async (req, res) => {
  const { postId } = req.query;
  if (!postId) return res.status(400).json({ error: "postId is required" });

  const result = await ddb.send(
    new QueryCommand({
      TableName: TABLE,
      KeyConditionExpression: "PK = :pk AND begins_with(SK, :prefix)",
      ExpressionAttributeValues: {
        ":pk": `POST#${postId}`,
        ":prefix": "COMMENT#",
      },
    })
  );

  res.json(result.Items ?? []);
});

// POST /api/comments  { postId, author, body }
app.post("/api/comments", async (req, res) => {
  const { postId, author, body } = req.body ?? {};
  if (!postId || !body) {
    return res.status(400).json({ error: "postId and body are required" });
  }

  const commentId = randomUUID();
  const item = {
    PK: `POST#${postId}`,
    SK: `COMMENT#${commentId}`,
    author: author || "Anonymous",
    body,
    createdAt: new Date().toISOString(),
  };

  await ddb.send(new PutCommand({ TableName: TABLE, Item: item }));

  if (TOPIC_ARN) {
    await sns.send(
      new PublishCommand({
        TopicArn: TOPIC_ARN,
        Subject: "New blog comment",
        Message: `New comment on post ${postId} from ${item.author}: ${body}`,
      })
    );
  }

  res.status(201).json(item);
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`comments-api listening on ${PORT}`);
});
