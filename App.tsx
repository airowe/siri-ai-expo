import { StatusBar } from 'expo-status-bar';
import * as AppIntents from 'expo-app-intents';
import { requireNativeModule } from 'expo';
import { useEffect, useState } from 'react';
import { Button, StyleSheet, Text, View } from 'react-native';

type AuthModule = {
  signInAsync(): Promise<void>;
  signOut(): void;
  lastToolOutcome(): string;
};

const Auth = requireNativeModule<AuthModule>('AppIntentsSetup');

const ORDERS: AppIntents.AppIntentEntity[] = [
  {
    id: 'order-shoes',
    title: 'Trail running shoes',
    synonyms: ['sneakers', 'shoes'],
    metadata: { status: 'out for delivery', arrival: 'today by 6 PM' },
  },
  {
    id: 'order-lamp',
    title: 'Brass desk lamp',
    synonyms: ['lamp', 'light'],
    metadata: { status: 'shipped', arrival: 'on Friday' },
  },
  {
    id: 'order-coffee',
    title: 'Ethiopian coffee beans',
    synonyms: ['coffee', 'beans'],
    metadata: { status: 'preparing', arrival: 'next week' },
  },
];

const STEP_TIMEOUT_MS = 20_000;
// Siri runs the tool while the app may stay active, so an app-state change can't be relied on.
const OUTCOME_POLL_MS = 1_000;

export default function App() {
  const [message, setMessage] = useState('Publishing orders…');
  const [authMessage, setAuthMessage] = useState('Signing in…');
  const [toolOutcome, setToolOutcome] = useState(Auth.lastToolOutcome());

  const signIn = async () => {
    setAuthMessage('Signing in…');
    try {
      await Auth.signInAsync();
      setAuthMessage(`Signed in at ${new Date().toLocaleTimeString()}, token lasts 1 minute`);
    } catch (error) {
      setAuthMessage(`Sign-in FAILED: ${String(error)}`);
    }
  };

  const signOut = () => {
    Auth.signOut();
    setAuthMessage('Signed out');
  };

  const publish = async () => {
    const lines: string[] = [];
    const step = async (name: string, run: () => Promise<unknown>) => {
      const timeout = new Promise<string>((resolve) =>
        setTimeout(() => resolve('TIMED OUT'), STEP_TIMEOUT_MS)
      );
      const outcome = await Promise.race([
        run().then(
          () => 'ok',
          (error) => `FAILED: ${String(error)}`
        ),
        timeout,
      ]);
      lines.push(`${name}: ${outcome}`);
      setMessage(lines.join('\n'));
    };

    setMessage('Publishing orders…');
    await step('Publish', () => AppIntents.setEntityCatalogAsync('order', ORDERS));
    await step('Read back', async () => {
      const stored = await AppIntents.getEntityCatalogAsync('order');
      if (stored.length !== ORDERS.length) throw new Error(`found ${stored.length} orders`);
    });
    await step('Spotlight', () => AppIntents.reindexEntitiesAsync('order'));
  };

  useEffect(() => {
    publish();
    signIn();
    const poll = setInterval(() => setToolOutcome(Auth.lastToolOutcome()), OUTCOME_POLL_MS);
    return () => clearInterval(poll);
  }, []);

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Siri Spike</Text>
      <Text testID="catalog-status">{message}</Text>
      {ORDERS.map((order) => (
        <Text key={order.id}>
          {order.title}: {order.metadata?.status}, {order.metadata?.arrival}
        </Text>
      ))}
      <Button title="Publish again" onPress={publish} />
      <Text testID="auth-status">{authMessage}</Text>
      <Text testID="tool-outcome">Last cart tool call: {toolOutcome}</Text>
      <Button title="Sign in again" onPress={signIn} />
      <Button title="Sign out" onPress={signOut} />
      <StatusBar style="auto" />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, gap: 12, padding: 24, justifyContent: 'center', backgroundColor: '#fff' },
  title: { fontSize: 24, fontWeight: '600' },
});
