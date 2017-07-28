RSpec.describe EventSourcery::Postgres::OptimisedEventPollWaiter do
  let(:after_listen) { proc {} }
  subject(:waiter) { described_class.new(db_connection: db_connection, after_listen: after_listen) }

  before do
    allow(EventSourcery::Postgres::QueueWithIntervalCallback).to receive(:new)
      .and_return(EventSourcery::Postgres::QueueWithIntervalCallback.new(callback_interval: 0))
  end

  def notify_event_ids(*ids)
    ids.each do |id|
      db_connection.notify('new_event', payload: id)
    end
  end

  it 'does an initial call' do
    waiter.poll(after_listen: proc {}) do
      @called = true
      throw :stop
    end

    expect(@called).to eq true
  end

  it 'calls on new event' do
    waiter.poll(after_listen: proc { notify_event_ids(1) }) do
      @called = true
      throw :stop
    end

    expect(@called).to eq true
  end

  it 'calls once when multiple events are in the queue' do
    waiter.poll(after_listen: proc { notify_event_ids(1, 2) }) do
      @called = true
      throw :stop
    end

    expect(@called).to eq true
  end

  context 'when the listening thread dies' do
    before do
      allow(db_connection).to receive(:listen).and_raise(StandardError)
    end

    it 'raise an error' do
      expect {
        waiter.poll {}
      }.to raise_error(described_class::ListenThreadDied)
    end
  end

  context 'when an error is raised' do
    let(:thread) { double }

    before { allow(Thread).to receive(:new).and_return(thread) }

    context 'when the listening thread is alive' do
      it 'kills the listening thread' do
        allow(thread).to receive(:alive?).and_return(true)
        expect(thread).to receive(:kill)

        waiter.poll(after_listen: proc { notify_event_ids(1) }) do
          @called = true
          throw :stop
        end
      end
    end

    context 'when the listening thread is not alive' do
      it 'does not try to kill any listening threads' do
        allow(thread).to receive(:alive?).and_return(false)
        expect(thread).to_not receive(:kill)

        waiter.poll(after_listen: proc { notify_event_ids(1) }) do
          @called = true
          throw :stop
        end
      end
    end
  end
end
