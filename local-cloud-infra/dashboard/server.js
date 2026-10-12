const express = require('express');
const cors = require('cors');
const path = require('path');
const multer = require('multer');
const http = require('http');

const { S3Client, ListBucketsCommand, ListObjectsV2Command, PutObjectCommand, DeleteObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');
const { DynamoDBClient, ListTablesCommand, DescribeTableCommand } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, ScanCommand, PutCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');
const { SQSClient, ListQueuesCommand, GetQueueAttributesCommand, SendMessageCommand, PurgeQueueCommand } = require('@aws-sdk/client-sqs');
const { SNSClient, ListTopicsCommand, PublishCommand } = require('@aws-sdk/client-sns');
const { LambdaClient, ListFunctionsCommand, InvokeCommand } = require('@aws-sdk/client-lambda');

const app = express();
const PORT = process.env.PORT || 3000;

// Configuration
const LOCALSTACK_ENDPOINT = process.env.LOCALSTACK_ENDPOINT || 'http://localhost:4566';
const AWS_REGION = process.env.AWS_DEFAULT_REGION || 'us-east-1';
const credentials = {
  accessKeyId: process.env.AWS_ACCESS_KEY_ID || 'test',
  secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY || 'test'
};

const awsConfig = {
  endpoint: LOCALSTACK_ENDPOINT,
  region: AWS_REGION,
  credentials
};

// S3 requires path-style addressing for LocalStack
const s3Client = new S3Client({
  ...awsConfig,
  forcePathStyle: true
});

const rawDdbClient = new DynamoDBClient(awsConfig);
const ddbDocClient = DynamoDBDocumentClient.from(rawDdbClient);
const sqsClient = new SQSClient(awsConfig);
const snsClient = new SNSClient(awsConfig);
const lambdaClient = new LambdaClient(awsConfig);

const upload = multer({ storage: multer.memoryStorage() });

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// -------------------------------------------------------------
// Health & Service Status
// -------------------------------------------------------------
app.get('/api/status', async (req, res) => {
  try {
    const healthUrl = `${LOCALSTACK_ENDPOINT}/_localstack/health`;
    const response = await fetch(healthUrl, { signal: AbortSignal.timeout(3000) });
    if (!response.ok) {
      return res.status(502).json({ online: false, error: `LocalStack returned HTTP ${response.status}` });
    }
    const data = await response.json();
    res.json({
      online: true,
      endpoint: LOCALSTACK_ENDPOINT,
      region: AWS_REGION,
      services: data.services || {}
    });
  } catch (err) {
    res.json({
      online: false,
      endpoint: LOCALSTACK_ENDPOINT,
      region: AWS_REGION,
      error: err.message || 'Cannot reach LocalStack endpoint'
    });
  }
});

// -------------------------------------------------------------
// Full Infrastructure Overview
// -------------------------------------------------------------
app.get('/api/overview', async (req, res) => {
  const result = {
    s3Buckets: [],
    dynamoTables: [],
    sqsQueues: [],
    snsTopics: [],
    lambdaFunctions: [],
    timestamp: new Date().toISOString()
  };

  try {
    // S3
    try {
      const s3Res = await s3Client.send(new ListBucketsCommand({}));
      result.s3Buckets = (s3Res.Buckets || []).map(b => ({ name: b.Name, creationDate: b.CreationDate }));
    } catch (e) {
      result.s3Error = e.message;
    }

    // DynamoDB
    try {
      const ddbRes = await rawDdbClient.send(new ListTablesCommand({}));
      result.dynamoTables = ddbRes.TableNames || [];
    } catch (e) {
      result.dynamoError = e.message;
    }

    // SQS
    try {
      const sqsRes = await sqsClient.send(new ListQueuesCommand({}));
      result.sqsQueues = sqsRes.QueueUrls || [];
    } catch (e) {
      result.sqsError = e.message;
    }

    // SNS
    try {
      const snsRes = await snsClient.send(new ListTopicsCommand({}));
      result.snsTopics = (snsRes.Topics || []).map(t => t.TopicArn);
    } catch (e) {
      result.snsError = e.message;
    }

    // Lambda
    try {
      const lmbRes = await lambdaClient.send(new ListFunctionsCommand({}));
      result.lambdaFunctions = (lmbRes.Functions || []).map(f => ({
        name: f.FunctionName,
        runtime: f.Runtime,
        handler: f.Handler,
        lastModified: f.LastModified
      }));
    } catch (e) {
      result.lambdaError = e.message;
    }

    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------------------------------------
// S3 API
// -------------------------------------------------------------
app.get('/api/s3/buckets', async (req, res) => {
  try {
    const data = await s3Client.send(new ListBucketsCommand({}));
    res.json(data.Buckets || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/s3/objects', async (req, res) => {
  const { bucket } = req.query;
  if (!bucket) return res.status(400).json({ error: 'Bucket parameter required' });
  try {
    const data = await s3Client.send(new ListObjectsV2Command({ Bucket: bucket }));
    res.json(data.Contents || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/s3/upload', upload.single('file'), async (req, res) => {
  const { bucket, key } = req.body;
  if (!bucket || !req.file) {
    return res.status(400).json({ error: 'Bucket and file are required' });
  }
  const fileKey = key || req.file.originalname;
  try {
    await s3Client.send(new PutObjectCommand({
      Bucket: bucket,
      Key: fileKey,
      Body: req.file.buffer,
      ContentType: req.file.mimetype
    }));
    res.json({ success: true, key: fileKey, size: req.file.size });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.delete('/api/s3/object', async (req, res) => {
  const { bucket, key } = req.query;
  if (!bucket || !key) return res.status(400).json({ error: 'Bucket and key required' });
  try {
    await s3Client.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------------------------------------
// DynamoDB API
// -------------------------------------------------------------
app.get('/api/dynamodb/tables', async (req, res) => {
  try {
    const data = await rawDdbClient.send(new ListTablesCommand({}));
    const tables = [];
    for (const tableName of (data.TableNames || [])) {
      try {
        const desc = await rawDdbClient.send(new DescribeTableCommand({ TableName: tableName }));
        tables.push({
          name: tableName,
          itemCount: desc.Table?.ItemCount ?? 0,
          status: desc.Table?.TableStatus,
          arn: desc.Table?.TableArn,
          keySchema: desc.Table?.KeySchema
        });
      } catch {
        tables.push({ name: tableName });
      }
    }
    res.json(tables);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/dynamodb/items', async (req, res) => {
  const { table } = req.query;
  if (!table) return res.status(400).json({ error: 'Table parameter required' });
  try {
    const data = await ddbDocClient.send(new ScanCommand({
      TableName: table,
      Limit: 50
    }));
    res.json(data.Items || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.delete('/api/dynamodb/item', async (req, res) => {
  const { table, pk, sk } = req.body;
  if (!table || !pk) return res.status(400).json({ error: 'Table and pk required' });
  try {
    const Key = { pk };
    if (sk !== undefined) Key.sk = sk;
    await ddbDocClient.send(new DeleteCommand({
      TableName: table,
      Key
    }));
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------------------------------------
// SQS API
// -------------------------------------------------------------
app.get('/api/sqs/queues', async (req, res) => {
  try {
    const data = await sqsClient.send(new ListQueuesCommand({}));
    const queueUrls = data.QueueUrls || [];
    const queues = [];

    for (const url of queueUrls) {
      const parts = url.split('/');
      const queueName = parts[parts.length - 1];
      let attributes = {};
      try {
        const attrRes = await sqsClient.send(new GetQueueAttributesCommand({
          QueueUrl: url,
          AttributeNames: ['ApproximateNumberOfMessages', 'ApproximateNumberOfMessagesNotVisible', 'QueueArn']
        }));
        attributes = attrRes.Attributes || {};
      } catch {}

      queues.push({
        url,
        name: queueName,
        messagesVisible: attributes.ApproximateNumberOfMessages || '0',
        messagesInFlight: attributes.ApproximateNumberOfMessagesNotVisible || '0',
        arn: attributes.QueueArn || ''
      });
    }
    res.json(queues);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/sqs/send', async (req, res) => {
  const { queueUrl, messageBody } = req.body;
  if (!queueUrl || !messageBody) return res.status(400).json({ error: 'queueUrl and messageBody required' });
  try {
    const data = await sqsClient.send(new SendMessageCommand({
      QueueUrl: queueUrl,
      MessageBody: typeof messageBody === 'object' ? JSON.stringify(messageBody) : String(messageBody)
    }));
    res.json({ success: true, messageId: data.MessageId });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/sqs/purge', async (req, res) => {
  const { queueUrl } = req.body;
  if (!queueUrl) return res.status(400).json({ error: 'queueUrl required' });
  try {
    await sqsClient.send(new PurgeQueueCommand({ QueueUrl: queueUrl }));
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------------------------------------
// SNS API
// -------------------------------------------------------------
app.get('/api/sns/topics', async (req, res) => {
  try {
    const data = await snsClient.send(new ListTopicsCommand({}));
    const topics = (data.Topics || []).map(t => {
      const parts = (t.TopicArn || '').split(':');
      return {
        arn: t.TopicArn,
        name: parts[parts.length - 1]
      };
    });
    res.json(topics);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/sns/publish', async (req, res) => {
  const { topicArn, message, subject } = req.body;
  if (!topicArn || !message) return res.status(400).json({ error: 'topicArn and message required' });
  try {
    const data = await snsClient.send(new PublishCommand({
      TopicArn: topicArn,
      Message: typeof message === 'object' ? JSON.stringify(message) : String(message),
      Subject: subject || 'Test Message from UI'
    }));
    res.json({ success: true, messageId: data.MessageId });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------------------------------------
// Lambda API
// -------------------------------------------------------------
app.get('/api/lambda/functions', async (req, res) => {
  try {
    const data = await lambdaClient.send(new ListFunctionsCommand({}));
    res.json(data.Functions || []);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/lambda/invoke', async (req, res) => {
  const { functionName, payload } = req.body;
  if (!functionName) return res.status(400).json({ error: 'functionName required' });
  try {
    const inputPayload = typeof payload === 'object' ? JSON.stringify(payload) : (payload || '{}');
    const data = await lambdaClient.send(new InvokeCommand({
      FunctionName: functionName,
      Payload: Buffer.from(inputPayload)
    }));

    let responsePayload = null;
    if (data.Payload) {
      try {
        responsePayload = JSON.parse(Buffer.from(data.Payload).toString('utf-8'));
      } catch {
        responsePayload = Buffer.from(data.Payload).toString('utf-8');
      }
    }

    res.json({
      statusCode: data.StatusCode,
      functionError: data.FunctionError,
      payload: responsePayload
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// -------------------------------------------------------------
// Pipeline Simulation (End-to-End Test Trigger)
// -------------------------------------------------------------
app.post('/api/pipeline/simulate', async (req, res) => {
  try {
    // 1. Locate SNS topic
    const snsData = await snsClient.send(new ListTopicsCommand({}));
    const topics = snsData.Topics || [];
    const targetTopic = topics.find(t => t.TopicArn.includes('local-events-topic')) || topics[0];

    if (!targetTopic) {
      return res.status(400).json({ error: 'No SNS topic found to publish to.' });
    }

    const testId = `sim-${Date.now().toString(36)}-${Math.random().toString(36).substring(2, 6)}`;
    const eventPayload = {
      eventId: testId,
      source: 'local-cloud-dashboard-ui',
      message: req.body.message || 'Simulated Pipeline Event',
      createdAt: new Date().toISOString()
    };

    // 2. Publish to SNS
    const pubRes = await snsClient.send(new PublishCommand({
      TopicArn: targetTopic.TopicArn,
      Message: JSON.stringify(eventPayload),
      Subject: 'Simulated Pipeline Event'
    }));

    // 3. Wait 1.5s for Lambda SQS consumer to execute and write to DynamoDB
    await new Promise(r => setTimeout(r, 1500));

    // 4. Check DynamoDB for updated records
    let latestItems = [];
    try {
      const ddbScan = await ddbDocClient.send(new ScanCommand({
        TableName: 'local-events-table',
        Limit: 10
      }));
      latestItems = ddbScan.Items || [];
    } catch {}

    res.json({
      success: true,
      publishedMessageId: pubRes.MessageId,
      topicArn: targetTopic.TopicArn,
      sentPayload: eventPayload,
      latestDynamoItemsCount: latestItems.length
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Start Server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 LocalStack Cloud Dashboard running at http://localhost:${PORT}`);
  console.log(`🔗 Connected to LocalStack endpoint: ${LOCALSTACK_ENDPOINT}`);
});

