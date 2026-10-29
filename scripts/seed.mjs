import { createPost } from "../src/lib/dynamo.js";

const table = process.env.DYNAMODB_TABLE;
if (!table) {
  console.log("DYNAMODB_TABLE not set. Set it before running: DYNAMODB_TABLE=<name> node scripts/seed.mjs");
  process.exit(1);
}

const samplePosts = [
  {
    slug: "welcome-to-aws-architecture",
    title: "Deploying a Multi-Tier Cloud System on AWS",
    description: "An overview of how this blog runs on EC2, Fargate, S3, DynamoDB, and Lambda.",
    author: "Hardik Kumar",
    tags: ["aws", "cloud", "architecture"],
    readingTime: "5 min read",
    body: `Welcome to this blog! This note is stored directly in an Amazon DynamoDB single-table schema and rendered dynamically by an Astro SSR application running on an EC2 instance behind an Application Load Balancer.

Every piece of this architecture is defined as Infrastructure as Code (IaC) via Terraform:
- **EC2 (Auto Scaling Group)**: Serves this SSR application.
- **ECS Fargate**: Hosts the decoupled comments and reactions microservice.
- **Amazon DynamoDB**: Single-table design for posts, comments, and newsletter subscribers.
- **Amazon S3 & CloudFront**: Media storage and global CDN caching.
- **AWS Lambda & SQS**: Background thumbnail processing and asynchronous welcome email queueing.
- **Amazon Cognito**: Secures the administrative publishing portal.`,
  },
  {
    slug: "notes-on-small-systems",
    title: "Small systems deserve a generous interface",
    description: "A blog starter that treats reading as the product: calm typography, spacious margins, fast pages.",
    author: "Hardik Kumar",
    tags: ["design", "software", "notes"],
    readingTime: "7 min read",
    body: `Good tools get quieter as your attention becomes more valuable. Most personal sites do not need a framework that ships a miniature application before the first sentence appears. They need a reliable publishing surface: one that opens quickly, gives prose enough room to breathe, and makes images, code, and asides feel like they belong together.`,
  },
];

console.log(`Seeding DynamoDB table: ${table}...`);
for (const post of samplePosts) {
  try {
    await createPost(post);
    console.log(`  ✓ Seeded post: ${post.slug}`);
  } catch (err) {
    console.error(`  ✗ Error seeding ${post.slug}:`, err.message);
  }
}
console.log("Seeding complete.");
