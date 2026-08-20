import React from 'react';
import {View, Text, StyleSheet} from 'react-native';

type Props = {
  text: string;
  mine: boolean;
  time?: string;
  read?: boolean;
};

export default function ChatBubble({text, mine, time, read}: Props) {
  return (
    <View style={[styles.wrapper, mine ? styles.wrapperMine : styles.wrapperOther]}>
      <View style={[styles.bubble, mine ? styles.myBubble : styles.otherBubble]}>
        <Text style={styles.text}>{text}</Text>
        <View style={styles.meta}>
          {time && (
            <Text style={[styles.time, mine ? styles.timeMine : styles.timeOther]}>
              {time}
            </Text>
          )}
          {mine && (
            <Text style={[styles.readTick, read && styles.readTickSeen]}>
              {read ? '✓✓' : '✓'}
            </Text>
          )}
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {marginVertical: 3, maxWidth: '80%'},
  wrapperMine: {alignSelf: 'flex-end'},
  wrapperOther: {alignSelf: 'flex-start'},
  bubble: {
    paddingHorizontal: 14,
    paddingTop: 10,
    paddingBottom: 8,
    borderRadius: 20,
  },
  myBubble: {
    backgroundColor: '#4F8CFF',
    borderBottomRightRadius: 4,
  },
  otherBubble: {
    backgroundColor: '#0F1C2E',
    borderBottomLeftRadius: 4,
    borderWidth: 0.5,
    borderColor: '#1E3A5F',
  },
  text: {color: 'white', fontSize: 15, lineHeight: 21},
  meta: {
    flexDirection: 'row', alignItems: 'center',
    justifyContent: 'flex-end', gap: 4, marginTop: 4,
  },
  time: {fontSize: 10},
  timeMine: {color: 'rgba(255,255,255,0.6)'},
  timeOther: {color: '#3D5A80'},
  readTick: {fontSize: 11, color: 'rgba(255,255,255,0.5)'},
  readTickSeen: {color: '#93C5FD'},
});