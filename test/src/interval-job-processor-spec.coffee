IntervalJobProcessor = require '../../src/interval-job-processor'
IORedis = require 'ioredis'
debug = require('debug')('mocha-test')
async = require 'async'

describe 'IntervalJobProcessor', ->
  beforeEach ->
    @kue = require 'kue'
    @redis = new IORedis
    @meshbluMessage = message: sinon.stub()
    dependencies = {}
    options = {
      minTimeDiff : 150
      @redis
      @meshbluMessage
      @kue
    }

    @queue = @kue.createQueue
      jobEvents: false

    @sut = new IntervalJobProcessor options

  beforeEach (done) ->
    @redis.del 'interval:pong:some-flow-id:some-node-id', done

  beforeEach (done) ->
    @redis.del "interval/job/some-flow-id/some-node-id", done

  beforeEach (done) ->
    @pingJob = @queue.create 'ping', {sendTo: 'some-flow-id', nodeId: 'some-node-id'}
    @pingJob.save done

  beforeEach (done) ->
    @intervalJob = @queue.create 'interval', {sendTo: 'some-flow-id', nodeId: 'some-node-id'}
    @intervalJob.save done

  beforeEach (done) ->
    @redis.sadd "interval/job/some-flow-id/some-node-id", @intervalJob.id, done

  beforeEach (done) ->
    @redis.sadd "interval/job/some-flow-id/some-node-id", @pingJob.id, done

  beforeEach (done) ->
    async.series [
      (callback) => @redis.set "interval/active/some-flow-id/some-node-id", 'active', callback
      (callback) => @redis.set "interval/time/some-flow-id/some-node-id", 'intervalTime', callback
      (callback) => @redis.set "interval/cron/some-flow-id/some-node-id", 'cronString', callback
    ], done

  describe '->processJob', ->
    describe 'when called with a job', ->
      beforeEach (done) ->
        @sut.processJob @intervalJob, {}, (error) => done error

      it 'should add a job', (done) ->
        @redis.exists 'interval/job/some-flow-id/some-node-id', (error, record) =>
          expect(JSON.parse record).to.equal 1
          done error

      it 'should add a pingJob', (done) ->
        @redis.exists 'interval/pingJob/some-flow-id/some-node-id', (error, record) =>
          expect(JSON.parse record).to.equal 1
          done error

  describe '->getJobs', ->
    describe 'when called with a job', ->
      beforeEach (done) ->
        @sut.getJobs @intervalJob, (error, @jobs) => done error

      it 'should return a list of jobs', ->
        expect(@jobs).to.deep.equal ["#{@pingJob.id}"]

  describe '->removeJob', ->
    describe 'when called with a job', ->
      beforeEach (done) ->
        @sut.removeJob @intervalJob.id, done

      it 'should remove the interval job', (done) ->
        @kue.Job.get @intervalJob.id, (error, job) =>
          expect(error).to.exist
          done()

  describe '->getJobInfo', ->
    describe 'when called with a job', ->
      beforeEach (done) ->
        @sut.getJobInfo @intervalJob, (error, @jobInfo) => done error

      it 'should yield jobInfo', ->
        jobInfo = ['active', 'intervalTime', 'cronString']
        expect(@jobInfo).to.deep.equal jobInfo

  describe '->calculateNextCronInterval', ->
    describe 'using a real date with milliseconds set to 0', ->
      now = new Date
      now.setMilliseconds(0)

      describe 'when called with seconds option', ->
        it 'should result in a next time of at most 1000 ms', ->
          result = @sut.calculateNextCronInterval "* * * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          nextSecond = nextDate.getSeconds()- now.getSeconds()
          if nextSecond == -59
            nextSecond = 1
          expect(nextSecond).to.equal 1
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(1000)

      describe 'when called with every 15 seconds option', ->
        it 'should result in a next time of at most 15000 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          expect(nextDate.getSeconds() % 15).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(15000)

      describe 'when called with minutes option', ->
        it 'should result in a next time of at most 60000 ms', ->
          result = @sut.calculateNextCronInterval "* * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          nextMinute = nextDate.getMinutes()- now.getMinutes()
          if nextMinute == -59
            nextMinute = 1
          expect(nextMinute).to.equal 1
          expect(nextDate.getSeconds()).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(60000)

      describe 'when called with every 15 minutes option', ->
        it 'should result in a next time of at most 900000 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          expect(nextDate.getMinutes() % 15).to.equal 0
          expect(nextDate.getSeconds()).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(900000)

    describe 'using a real date with milliseconds set to 0', ->
      now = new Date
      now.setMilliseconds(0)

      describe 'when called with seconds option', ->
        it 'should result in a next time of at most 1000 ms', ->
          result = @sut.calculateNextCronInterval "* * * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          nextSecond = nextDate.getSeconds()- now.getSeconds()
          if nextSecond == -59
            nextSecond = 1
          expect(nextSecond).to.equal 1
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(1000)

      describe 'when called with every 15 seconds option', ->
        it 'should result in a next time of at most 15000 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          expect(nextDate.getSeconds() % 15).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(15000)

      describe 'when called with minutes option', ->
        it 'should result in a next time of at most 60000 ms', ->
          result = @sut.calculateNextCronInterval "* * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          nextMinute = nextDate.getMinutes()- now.getMinutes()
          if nextMinute == -59
            nextMinute = 1
          expect(nextMinute).to.equal 1
          expect(nextDate.getSeconds()).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(60000)

      describe 'when called with every 15 minutes option', ->
        it 'should result in a next time of at most 900000 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * *", now
          nextDate = new Date(now.getTime() + result)
          debug 'result from', now, 'to', nextDate.toString(), result, 'ms'
          expect(nextDate.getMinutes() % 15).to.equal 0
          expect(nextDate.getSeconds()).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.be.at.most(900000)

    describe 'using a fake date', ->
      fakeDate = new Date(2015, 0, 1, 15, 0, 0, 0)

      describe 'when called with seconds option', ->
        it 'should result in a next time of 1000 ms', ->
          result = @sut.calculateNextCronInterval "* * * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          nextSecond = nextDate.getSeconds()- fakeDate.getSeconds()
          if nextSecond == -59
            nextSecond = 1
          expect(nextSecond).to.equal 1
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.equals(1000)

      describe 'when called with every 15 seconds option', ->
        it 'should result in a next time of 15000 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          expect(nextDate.getSeconds() % 15).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.equals(15000)

      describe 'when called with minutes option', ->
        it 'should result in a next time of 60000 ms', ->
          result = @sut.calculateNextCronInterval "* * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          nextMinute = nextDate.getMinutes()- fakeDate.getMinutes()
          if nextMinute == -59
            nextMinute = 1
          expect(nextMinute).to.equal 1
          expect(nextDate.getSeconds()).to.equal 0
          expect(result).to.equals(60000)

      describe 'when called with every 15 minutes option', ->
        it 'should result in a next time of 900000 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          expect(nextDate.getMinutes() % 15).to.equal 0
          expect(nextDate.getSeconds()).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.equals(900000)

      describe 'when called with an invalid cron string', ->
        it 'should throw an error', ->
          hasError = false
          try
            @sut.calculateNextCronInterval "*/1000E * * * * *", fakeDate
          catch error
            hasError = true
          expect(hasError).to.equals true

    describe 'using a fake date with milliseconds set close to an interval', ->
      fakeDate = new Date(2015, 0, 1, 12, 59, 59, 850)

      describe 'when called with seconds option', ->
        it 'should result in a next time of 1150 ms', ->
          result = @sut.calculateNextCronInterval "* * * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          nextSecond = nextDate.getSeconds()- fakeDate.getSeconds()
          if nextSecond < 0
            nextSecond = nextSecond + 60
          nextMinute = nextDate.getMinutes()- fakeDate.getMinutes()
          if nextMinute < 0
            nextMinute = nextMinute + 60
          nextHour = nextDate.getHours()- fakeDate.getHours()
          expect(nextSecond).to.equal 2
          expect(nextMinute).to.equal 1
          expect(nextHour).to.equal 1
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.equals(1150)

      describe 'when called with every 15 seconds option', ->
        it 'should result in a next time of 15150 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          expect(nextDate.getSeconds() % 15).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.equals(15150)

      describe 'when called with minutes option', ->
        it 'should result in a next time of 60150 ms', ->
          result = @sut.calculateNextCronInterval "* * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          nextMinute = nextDate.getMinutes()- fakeDate.getMinutes()
          if nextMinute < 0
            nextMinute = nextMinute + 60
          nextHour = nextDate.getHours()- fakeDate.getHours()
          expect(nextMinute).to.equal 2
          expect(nextHour).to.equal 1
          expect(nextDate.getSeconds()).to.equal 0
          expect(result).to.equals(60150)

      describe 'when called with every 15 minutes option', ->
        it 'should result in a next time of 900150 ms', ->
          result = @sut.calculateNextCronInterval "*/15 * * * *", fakeDate
          nextDate = new Date(fakeDate.getTime() + result)
          debug 'result from', fakeDate, 'to', new Date(fakeDate.getTime() + result).toString(), result, 'ms'
          expect(nextDate.getMinutes() % 15).to.equal 0
          expect(nextDate.getSeconds()).to.equal 0
          expect(nextDate.getMilliseconds()).to.equal 0
          expect(result).to.equals(900150)
