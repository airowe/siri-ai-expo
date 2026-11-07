import { StatusBar } from 'expo-status-bar';
import * as AppIntents from 'expo-app-intents';
import { useEffect, useState } from 'react';
import { Button, StyleSheet, Text, View } from 'react-native';

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

export default function App() {
  const [message, setMessage] = useState('Publishing orders…');

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
      <StatusBar style="auto" />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, gap: 12, padding: 24, justifyContent: 'center', backgroundColor: '#fff' },
  title: { fontSize: 24, fontWeight: '600' },
});
