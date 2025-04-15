# Demo docs

This demo shows how triggering an error results in a message being posted to Slack via our sre-agent bot.

To do this, the bot needs access to the Slack API, which requires a Slack bot token stored as a Kubernetes secret.

## Step 1: Check if the secret already exists
Run the following command:
```bash
kubectl describe secret slack-bot-secret
```

If the secret is present, you should see something like this:

```bash
Name:         slack-bot-secret
Namespace:    default
Labels:       <none>
Annotations:  <none>

Type:  Opaque

Data
====
SLACK_BOT_TOKEN:  56 bytes
```

## Step 2: Create the secret (if needed)
If the secret doesn’t exist, create it by running:
```bash
kubectl create secret generic slack-bot-secret \
  --from-literal=SLACK_BOT_TOKEN=<slack-bot-token>
```

Replace `<slack-bot-token>` with your actual Slack bot token.

